import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createOrgUnit,
  moveOrgUnit,
  renameOrgUnit,
  setOrgUnitStatus,
  OrgHierarchyMutationError,
  type OrgHierarchyRpcClient,
} from "./org-hierarchy.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const UNIT_ID = "323e4567-e89b-12d3-a456-426614174000";
const COMPANY_ID = "123e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: UNIT_ID,
  tenant_id: TENANT_ID,
  unit_type: "branch",
  parent_id: COMPANY_ID,
  code: "ACME-JKT",
  name: "Acme Jakarta Branch",
  status: "active",
  path: [COMPANY_ID],
  depth: 1,
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

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

describe("createOrgUnit", () => {
  test("calls create_org_unit with the exact snake_case params, defaulting parentId to null", async () => {
    const client = fakeClient({ data: { ...ROW, unit_type: "company", parent_id: null, path: [], depth: 0 }, error: null });
    await createOrgUnit(client, { tenantId: TENANT_ID, unitType: "company", code: "ACME-CO", name: "Acme Co", requestedBy: "tester" });

    assert.equal(client.calls[0]?.fn, "create_org_unit");
    assert.equal(client.calls[0]?.args.p_parent_id, null);
  });

  test("classifies a code conflict into its typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "org_unit_code_conflict: code ACME-JKT already exists for tenant with a different type/parent" } });
    await assert.rejects(
      () => createOrgUnit(client, { tenantId: TENANT_ID, unitType: "branch", parentId: COMPANY_ID, code: "ACME-JKT", name: "x", requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof OrgHierarchyMutationError);
        assert.equal(err.code, "org_unit_code_conflict");
        return true;
      },
    );
  });
});

describe("moveOrgUnit", () => {
  test("calls move_org_unit with the exact snake_case params", async () => {
    const client = fakeClient({ data: ROW, error: null });
    await moveOrgUnit(client, { id: UNIT_ID, newParentId: COMPANY_ID, expectedVersion: 1, requestedBy: "tester" });

    assert.equal(client.calls[0]?.fn, "move_org_unit");
    assert.equal(client.calls[0]?.args.p_new_parent_id, COMPANY_ID);
    assert.equal(client.calls[0]?.args.p_expected_version, 1);
  });

  test("classifies a cycle rejection distinctly from a version conflict", async () => {
    const cycleClient = fakeClient({ data: null, error: { message: "org_unit_cycle: cannot be moved under its own descendant" } });
    await assert.rejects(
      () => moveOrgUnit(cycleClient, { id: UNIT_ID, newParentId: COMPANY_ID, expectedVersion: 1, requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof OrgHierarchyMutationError);
        assert.equal(err.code, "org_unit_cycle");
        return true;
      },
    );

    const staleClient = fakeClient({ data: null, error: { message: "org_unit_version_conflict: expected version 1, found 2" } });
    await assert.rejects(
      () => moveOrgUnit(staleClient, { id: UNIT_ID, newParentId: COMPANY_ID, expectedVersion: 1, requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof OrgHierarchyMutationError);
        assert.equal(err.code, "org_unit_version_conflict");
        return true;
      },
    );
  });
});

describe("renameOrgUnit", () => {
  test("calls rename_org_unit with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...ROW, name: "New Name" }, error: null });
    await renameOrgUnit(client, { id: UNIT_ID, newName: "New Name", expectedVersion: 1, requestedBy: "tester" });

    assert.equal(client.calls[0]?.fn, "rename_org_unit");
    assert.equal(client.calls[0]?.args.p_new_name, "New Name");
  });
});

describe("setOrgUnitStatus", () => {
  test("calls set_org_unit_status with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...ROW, status: "inactive" }, error: null });
    await setOrgUnitStatus(client, { id: UNIT_ID, newStatus: "inactive", expectedVersion: 1, reason: "restructuring", requestedBy: "tester" });

    assert.equal(client.calls[0]?.fn, "set_org_unit_status");
    assert.equal(client.calls[0]?.args.p_new_status, "inactive");
    assert.equal(client.calls[0]?.args.p_reason, "restructuring");
  });

  test("classifies an active-children dependency conflict into its typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "org_unit_has_active_children: cannot be deactivated while 1 active child/children exist" } });
    await assert.rejects(
      () => setOrgUnitStatus(client, { id: UNIT_ID, newStatus: "inactive", expectedVersion: 1, reason: "x", requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof OrgHierarchyMutationError);
        assert.equal(err.code, "org_unit_has_active_children");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized database error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset by peer" } });
    await assert.rejects(
      () => setOrgUnitStatus(client, { id: UNIT_ID, newStatus: "inactive", expectedVersion: 1, reason: "x", requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof OrgHierarchyMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
