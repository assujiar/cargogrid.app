import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { CreateOrgUnitInputSchema, SetOrgUnitTaxIdInputSchema, parseOrgUnit } from "./org-hierarchy.ts";

const COMPANY_ID = "123e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

describe("parseOrgUnit", () => {
  test("maps a snake_case row to the camelCase contract shape, including the path array", () => {
    const unit = parseOrgUnit({
      id: "323e4567-e89b-12d3-a456-426614174000",
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
    });

    assert.equal(unit.unitType, "branch");
    assert.deepEqual(unit.path, [COMPANY_ID]);
    assert.equal(unit.depth, 1);
  });

  test("rejects an unknown unit_type -- the four node types are closed", () => {
    assert.throws(() =>
      parseOrgUnit({
        id: "323e4567-e89b-12d3-a456-426614174000",
        tenant_id: TENANT_ID,
        unit_type: "region",
        parent_id: null,
        code: "X",
        name: "X",
        status: "active",
        path: [],
        depth: 0,
        record_version: 1,
        created_at: "2026-07-16T00:00:00.000Z",
        updated_at: "2026-07-16T00:00:00.000Z",
      }),
    );
  });

  test("CG-AUDIT-2026-09-02 C1: maps tax_id when present", () => {
    const unit = parseOrgUnit({
      id: "323e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      unit_type: "company",
      parent_id: null,
      code: "ACME-CO",
      name: "Acme Co",
      status: "active",
      tax_id: "01.234.567.8-901.000",
      path: [],
      depth: 0,
      record_version: 1,
      created_at: "2026-07-16T00:00:00.000Z",
      updated_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(unit.taxId, "01.234.567.8-901.000");
  });

  test("CG-AUDIT-2026-09-02 C1: defaults taxId to null when the raw row omits it (every pre-existing org unit)", () => {
    const unit = parseOrgUnit({
      id: "323e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      unit_type: "company",
      parent_id: null,
      code: "ACME-CO",
      name: "Acme Co",
      status: "active",
      path: [],
      depth: 0,
      record_version: 1,
      created_at: "2026-07-16T00:00:00.000Z",
      updated_at: "2026-07-16T00:00:00.000Z",
    });
    assert.equal(unit.taxId, null);
  });
});

describe("CreateOrgUnitInputSchema", () => {
  test("defaults parentId to null for a root company", () => {
    const parsed = CreateOrgUnitInputSchema.parse({
      tenantId: TENANT_ID,
      unitType: "company",
      code: "ACME-CO",
      name: "Acme Co",
      requestedBy: "tester",
    });
    assert.equal(parsed.parentId, null);
  });
});

describe("SetOrgUnitTaxIdInputSchema", () => {
  test("accepts a real tax ID string", () => {
    const parsed = SetOrgUnitTaxIdInputSchema.parse({
      id: "323e4567-e89b-12d3-a456-426614174000",
      newTaxId: "01.234.567.8-901.000",
      expectedVersion: 1,
      requestedBy: "tester",
    });
    assert.equal(parsed.newTaxId, "01.234.567.8-901.000");
  });

  test("accepts null -- clears a previously-set tax ID", () => {
    const parsed = SetOrgUnitTaxIdInputSchema.parse({
      id: "323e4567-e89b-12d3-a456-426614174000",
      newTaxId: null,
      expectedVersion: 1,
      requestedBy: "tester",
    });
    assert.equal(parsed.newTaxId, null);
  });
});
