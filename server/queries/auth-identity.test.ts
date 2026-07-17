import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listIdentityTenantLinks, IdentityLookupError, type IdentityLookupClient } from "./auth-identity.ts";

const ROW = {
  id: "323e4567-e89b-12d3-a456-426614174000",
  auth_user_id: "123e4567-e89b-12d3-a456-426614174000",
  tenant_id: "223e4567-e89b-12d3-a456-426614174000",
  status: "active",
  invited_by: "supreme-admin-1",
  invited_at: "2026-07-16T00:00:00.000Z",
  activated_at: "2026-07-16T00:00:00.000Z",
  revoked_at: null,
  revoked_reason: null,
  mfa_enrolled: false,
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

describe("listIdentityTenantLinks", () => {
  test("filters by auth_user_id and maps every row", async () => {
    let capturedColumn = "";
    let capturedValue = "";
    const client: IdentityLookupClient = {
      from: () => ({
        select: () => ({
          eq: async (column, value) => {
            capturedColumn = column;
            capturedValue = value;
            return { data: [ROW], error: null };
          },
        }),
      }),
    };

    const links = await listIdentityTenantLinks(client, "123e4567-e89b-12d3-a456-426614174000");
    assert.equal(capturedColumn, "auth_user_id");
    assert.equal(capturedValue, "123e4567-e89b-12d3-a456-426614174000");
    assert.equal(links.length, 1);
    assert.equal(links[0]?.status, "active");
  });

  test("returns an empty array when the identity has no linkages, not an error", async () => {
    const client: IdentityLookupClient = {
      from: () => ({ select: () => ({ eq: async () => ({ data: [], error: null }) }) }),
    };
    const links = await listIdentityTenantLinks(client, "123e4567-e89b-12d3-a456-426614174000");
    assert.deepEqual(links, []);
  });

  test("wraps a database error into IdentityLookupError", async () => {
    const client: IdentityLookupClient = {
      from: () => ({ select: () => ({ eq: async () => ({ data: null, error: { message: "connection reset" } }) }) }),
    };
    await assert.rejects(() => listIdentityTenantLinks(client, "123e4567-e89b-12d3-a456-426614174000"), IdentityLookupError);
  });
});
