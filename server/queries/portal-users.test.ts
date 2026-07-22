import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listPortalUsers, PortalUsersQueryError } from "./portal-users.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";

const ROWS = [
  { id: "223e4567-e89b-12d3-a456-426614174000", display_name: "Ada Lovelace", status: "active", email: "a***@example.test", email_masked: true },
  { id: "323e4567-e89b-12d3-a456-426614174000", display_name: "Bob Marley", status: "invited", email: "b***@example.test", email_masked: true },
];

interface FakeQueryState {
  readonly capturedFilters: { tenantId?: string; range?: [number, number] };
}

function fakeClient(response: { data: unknown; error: { message: string } | null; count: number | null }, state: FakeQueryState) {
  return {
    from(_table: string) {
      return {
        select(_columns: string, _opts?: { count?: string }) {
          return {
            eq(column: string, value: string) {
              if (column === "tenant_id") state.capturedFilters.tenantId = value;
              return this;
            },
            order(_column: string, _opts?: { ascending?: boolean }) {
              return this;
            },
            async range(from: number, to: number) {
              state.capturedFilters.range = [from, to];
              return response;
            },
          };
        },
      };
    },
  };
}

describe("listPortalUsers", () => {
  test("returns typed users and total count on success", async () => {
    const state: FakeQueryState = { capturedFilters: {} };
    const client = fakeClient({ data: ROWS, error: null, count: 2 }, state);
    const result = await listPortalUsers(client as never, { tenantId: TENANT_ID, page: 1, pageSize: 20 });

    assert.equal(result.users.length, 2);
    assert.equal(result.users[0]?.displayName, "Ada Lovelace");
    assert.equal(result.totalCount, 2);
  });

  test("filters by the given tenant_id (never merges another tenant's users)", async () => {
    const state: FakeQueryState = { capturedFilters: {} };
    const client = fakeClient({ data: ROWS, error: null, count: 2 }, state);
    await listPortalUsers(client as never, { tenantId: TENANT_ID, page: 1, pageSize: 20 });

    assert.equal(state.capturedFilters.tenantId, TENANT_ID);
  });

  test("clamps an over-limit pageSize to the governed maximum of 100", async () => {
    const state: FakeQueryState = { capturedFilters: {} };
    const client = fakeClient({ data: [], error: null, count: 0 }, state);
    const result = await listPortalUsers(client as never, { tenantId: TENANT_ID, page: 1, pageSize: 5000 });

    assert.equal(result.pageSize, 100);
    assert.deepEqual(state.capturedFilters.range, [0, 99]);
  });

  test("clamps a zero/negative pageSize up to 1", async () => {
    const state: FakeQueryState = { capturedFilters: {} };
    const client = fakeClient({ data: [], error: null, count: 0 }, state);
    const result = await listPortalUsers(client as never, { tenantId: TENANT_ID, page: 1, pageSize: 0 });

    assert.equal(result.pageSize, 1);
  });

  test("computes the correct range for page 2", async () => {
    const state: FakeQueryState = { capturedFilters: {} };
    const client = fakeClient({ data: [], error: null, count: 0 }, state);
    await listPortalUsers(client as never, { tenantId: TENANT_ID, page: 2, pageSize: 20 });

    assert.deepEqual(state.capturedFilters.range, [20, 39]);
  });

  test("wraps a database error into PortalUsersQueryError", async () => {
    const state: FakeQueryState = { capturedFilters: {} };
    const client = fakeClient({ data: null, error: { message: "connection reset" }, count: null }, state);
    await assert.rejects(() => listPortalUsers(client as never, { tenantId: TENANT_ID, page: 1, pageSize: 20 }), PortalUsersQueryError);
  });

  test("returns an empty list, not an error, for a tenant with zero users", async () => {
    const state: FakeQueryState = { capturedFilters: {} };
    const client = fakeClient({ data: [], error: null, count: 0 }, state);
    const result = await listPortalUsers(client as never, { tenantId: TENANT_ID, page: 1, pageSize: 20 });

    assert.deepEqual(result.users, []);
    assert.equal(result.totalCount, 0);
  });
});
