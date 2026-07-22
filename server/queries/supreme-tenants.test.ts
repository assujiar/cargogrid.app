import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listSupremeTenants, SupremeTenantsQueryError } from "./supreme-tenants.ts";

const ROWS = [
  { id: "223e4567-e89b-12d3-a456-426614174000", slug: "acme", name: "Acme Co", canonical_status: "active" },
  { id: "323e4567-e89b-12d3-a456-426614174000", slug: "gizmo", name: "Gizmo Inc", canonical_status: "suspended" },
];

interface FakeQueryState {
  readonly captured: { range?: [number, number] };
}

function fakeClient(response: { data: unknown; error: { message: string } | null; count: number | null }, state: FakeQueryState) {
  return {
    from(_table: string) {
      return {
        select(_columns: string, _opts?: { count?: string }) {
          return {
            order(_column: string, _opts?: { ascending?: boolean }) {
              return this;
            },
            async range(from: number, to: number) {
              state.captured.range = [from, to];
              return response;
            },
          };
        },
      };
    },
  };
}

describe("listSupremeTenants", () => {
  test("returns typed tenants and total count on success", async () => {
    const state: FakeQueryState = { captured: {} };
    const client = fakeClient({ data: ROWS, error: null, count: 2 }, state);
    const result = await listSupremeTenants(client as never, { page: 1, pageSize: 20 });

    assert.equal(result.tenants.length, 2);
    assert.equal(result.tenants[0]?.slug, "acme");
    assert.equal(result.totalCount, 2);
  });

  test("clamps an over-limit pageSize to the governed maximum of 100", async () => {
    const state: FakeQueryState = { captured: {} };
    const client = fakeClient({ data: [], error: null, count: 0 }, state);
    const result = await listSupremeTenants(client as never, { page: 1, pageSize: 5000 });

    assert.equal(result.pageSize, 100);
    assert.deepEqual(state.captured.range, [0, 99]);
  });

  test("clamps a zero/negative pageSize up to 1", async () => {
    const state: FakeQueryState = { captured: {} };
    const client = fakeClient({ data: [], error: null, count: 0 }, state);
    const result = await listSupremeTenants(client as never, { page: 1, pageSize: 0 });

    assert.equal(result.pageSize, 1);
  });

  test("computes the correct range for page 2", async () => {
    const state: FakeQueryState = { captured: {} };
    const client = fakeClient({ data: [], error: null, count: 0 }, state);
    await listSupremeTenants(client as never, { page: 2, pageSize: 20 });

    assert.deepEqual(state.captured.range, [20, 39]);
  });

  test("wraps a database error into SupremeTenantsQueryError", async () => {
    const state: FakeQueryState = { captured: {} };
    const client = fakeClient({ data: null, error: { message: "connection reset" }, count: null }, state);
    await assert.rejects(() => listSupremeTenants(client as never, { page: 1, pageSize: 20 }), SupremeTenantsQueryError);
  });

  test("returns an empty list, not an error, when there are zero tenants", async () => {
    const state: FakeQueryState = { captured: {} };
    const client = fakeClient({ data: [], error: null, count: 0 }, state);
    const result = await listSupremeTenants(client as never, { page: 1, pageSize: 20 });

    assert.deepEqual(result.tenants, []);
    assert.equal(result.totalCount, 0);
  });
});
