import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getOrgUnitAncestorIds, getOrgUnitDescendantIds, listOrgUnits, OrgHierarchyQueryError, type OrgHierarchyRpcClient } from "./org-hierarchy.ts";

const ORG_UNIT_ID = "323e4567-e89b-12d3-a456-426614174000";
const COMPANY_ID = "123e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): OrgHierarchyRpcClient & {
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("getOrgUnitAncestorIds", () => {
  test("calls org_unit_ancestor_ids with the exact snake_case param", async () => {
    const client = fakeClient({ data: [COMPANY_ID], error: null });
    const ancestors = await getOrgUnitAncestorIds(client, ORG_UNIT_ID);

    assert.equal(client.calls[0]?.fn, "org_unit_ancestor_ids");
    assert.equal(client.calls[0]?.args.p_id, ORG_UNIT_ID);
    assert.deepEqual(ancestors, [COMPANY_ID]);
  });

  test("returns an empty array for a root node rather than throwing", async () => {
    const client = fakeClient({ data: [], error: null });
    const ancestors = await getOrgUnitAncestorIds(client, COMPANY_ID);
    assert.deepEqual(ancestors, []);
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => getOrgUnitAncestorIds(client, ORG_UNIT_ID), OrgHierarchyQueryError);
  });
});

describe("getOrgUnitDescendantIds", () => {
  test("calls org_unit_descendant_ids with the exact snake_case param", async () => {
    const client = fakeClient({ data: [ORG_UNIT_ID], error: null });
    const descendants = await getOrgUnitDescendantIds(client, COMPANY_ID);

    assert.equal(client.calls[0]?.fn, "org_unit_descendant_ids");
    assert.equal(client.calls[0]?.args.p_id, COMPANY_ID);
    assert.deepEqual(descendants, [ORG_UNIT_ID]);
  });

  test("rejects a non-array success response rather than fabricating a result", async () => {
    const client = fakeClient({ data: { unexpected: true }, error: null });
    await assert.rejects(() => getOrgUnitDescendantIds(client, COMPANY_ID), OrgHierarchyQueryError);
  });
});

describe("listOrgUnits", () => {
  test("maps rows and passes the exact snake_case params, including the optional filters", async () => {
    const client = fakeClient({ data: [{ id: ORG_UNIT_ID, name: "Finance", unit_type: "department" }], error: null });
    const units = await listOrgUnits(client, TENANT_ID, { statusFilter: "active", unitTypeFilter: "department" });

    assert.equal(client.calls[0]?.fn, "list_org_units");
    assert.deepEqual(client.calls[0]?.args, { p_tenant_id: TENANT_ID, p_status_filter: "active", p_unit_type_filter: "department" });
    assert.deepEqual(units, [{ id: ORG_UNIT_ID, name: "Finance", unitType: "department" }]);
  });

  test("defaults both filters to null when omitted", async () => {
    const client = fakeClient({ data: [], error: null });
    await listOrgUnits(client, TENANT_ID);
    assert.deepEqual(client.calls[0]?.args, { p_tenant_id: TENANT_ID, p_status_filter: null, p_unit_type_filter: null });
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listOrgUnits(client, TENANT_ID), OrgHierarchyQueryError);
  });

  test("rejects a non-array success response rather than fabricating a result", async () => {
    const client = fakeClient({ data: { unexpected: true }, error: null });
    await assert.rejects(() => listOrgUnits(client, TENANT_ID), OrgHierarchyQueryError);
  });
});
