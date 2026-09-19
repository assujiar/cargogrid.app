import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listSupremeTenants, SupremeTenantsQueryError } from "./supreme-tenants.ts";

const ROWS = [
  { id: "223e4567-e89b-12d3-a456-426614174000", slug: "acme", name: "Acme Co", canonical_status: "active", total_count: 2 },
  { id: "323e4567-e89b-12d3-a456-426614174000", slug: "gizmo", name: "Gizmo Inc", canonical_status: "suspended", total_count: 2 },
];

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: { rpc: (fn: string, args: Record<string, unknown>) => Promise<typeof response> };
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  };
  return { client, calls };
}

describe("listSupremeTenants", () => {
  test("returns typed tenants and total count on success", async () => {
    const { client } = fakeRpcClient({ data: ROWS, error: null });
    const result = await listSupremeTenants(client as never, { page: 1, pageSize: 20 });

    assert.equal(result.tenants.length, 2);
    assert.equal(result.tenants[0]?.slug, "acme");
    assert.equal(result.totalCount, 2);
  });

  test("clamps an over-limit pageSize to the governed maximum of 100", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    const result = await listSupremeTenants(client as never, { page: 1, pageSize: 5000 });

    assert.equal(result.pageSize, 100);
    assert.equal(calls[0]?.args.p_page_size, 100);
  });

  test("clamps a zero/negative pageSize up to 1", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listSupremeTenants(client as never, { page: 1, pageSize: 0 });

    assert.equal(result.pageSize, 1);
  });

  test("passes the requested page straight through as p_page", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listSupremeTenants(client as never, { page: 2, pageSize: 20 });

    assert.equal(calls[0]?.fn, "list_supreme_tenants");
    assert.deepEqual(calls[0]?.args, { p_page: 2, p_page_size: 20 });
  });

  test("wraps a database error into SupremeTenantsQueryError", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listSupremeTenants(client as never, { page: 1, pageSize: 20 }), SupremeTenantsQueryError);
  });

  test("returns an empty list, not an error, when there are zero tenants", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listSupremeTenants(client as never, { page: 1, pageSize: 20 });

    assert.deepEqual(result.tenants, []);
    assert.equal(result.totalCount, 0);
  });
});
