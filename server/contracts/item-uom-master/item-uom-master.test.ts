import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseItemMaster, parseUom, CreateItemMasterInputSchema, ItemMasterSchema, UomSchema } from "./item-uom-master.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseItemMaster", () => {
  test("maps an active, lot+expiry-controlled item master row", () => {
    const item = parseItemMaster({
      id: ITEM_ID,
      tenant_id: TENANT_ID,
      owner_account_id: ACCOUNT_ID,
      code: "SKU-100",
      name: "Test Widget",
      description: "A test widget",
      base_uom_code: "PCS",
      lot_controlled: true,
      serial_controlled: false,
      expiry_controlled: true,
      status: "active",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(item.code, "SKU-100");
    assert.equal(item.lotControlled, true);
    assert.equal(item.serialControlled, false);
    assert.equal(item.expiryControlled, true);
    assert.equal(item.ownerAccountId, ACCOUNT_ID);
  });

  test("defaults description/createdBy to null when absent", () => {
    const item = parseItemMaster({
      id: ITEM_ID,
      tenant_id: TENANT_ID,
      owner_account_id: ACCOUNT_ID,
      code: "SKU-200",
      name: "Another Widget",
      base_uom_code: "KG",
      lot_controlled: false,
      serial_controlled: false,
      expiry_controlled: false,
      status: "active",
      record_version: 1,
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(item.description, null);
    assert.equal(item.createdBy, null);
  });

  test("rejects an invalid status via the schema", () => {
    assert.throws(() =>
      ItemMasterSchema.parse({
        id: ITEM_ID,
        tenantId: TENANT_ID,
        ownerAccountId: ACCOUNT_ID,
        code: "SKU-100",
        name: "Test Widget",
        description: null,
        baseUomCode: "PCS",
        lotControlled: false,
        serialControlled: false,
        expiryControlled: false,
        status: "discontinued",
        recordVersion: 1,
        createdBy: null,
        createdAt: "2026-08-03T00:00:00.000Z",
        updatedAt: "2026-08-03T00:00:00.000Z",
      }),
    );
  });
});

describe("parseUom", () => {
  test("maps a weight-category UOM row", () => {
    const uom = parseUom({ code: "KG", name: "Kilogram", unit_category: "weight", is_active: true });
    assert.equal(uom.code, "KG");
    assert.equal(uom.unitCategory, "weight");
  });

  test("rejects an unrecognized unit_category via the schema", () => {
    assert.throws(() => UomSchema.parse({ code: "BOX", name: "Box", unitCategory: "packaging", isActive: true }));
  });
});

describe("CreateItemMasterInputSchema", () => {
  test("requires a non-empty code and name", () => {
    assert.throws(() =>
      CreateItemMasterInputSchema.parse({
        tenantId: TENANT_ID,
        ownerAccountId: ACCOUNT_ID,
        code: "",
        name: "Test Widget",
        description: null,
        baseUomCode: "PCS",
        lotControlled: false,
        serialControlled: false,
        expiryControlled: false,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts a fully-specified input", () => {
    const parsed = CreateItemMasterInputSchema.parse({
      tenantId: TENANT_ID,
      ownerAccountId: ACCOUNT_ID,
      code: "SKU-100",
      name: "Test Widget",
      description: null,
      baseUomCode: "PCS",
      lotControlled: true,
      serialControlled: false,
      expiryControlled: true,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.code, "SKU-100");
    assert.equal(parsed.lotControlled, true);
  });
});
