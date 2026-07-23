import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { ConvertLeadToProspectInputSchema, ConversionReadinessSchema, parseProspect } from "./prospect.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEAD_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("ConvertLeadToProspectInputSchema", () => {
  test("applies defaults for omitted optional fields", () => {
    const parsed = ConvertLeadToProspectInputSchema.parse({
      leadId: LEAD_ID,
      legalName: "Contoso Ltd",
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });
    assert.equal(parsed.tradeName, null);
    assert.equal(parsed.taxId, null);
    assert.deepEqual(parsed.billingAddress, {});
  });

  test("rejects an empty legal name", () => {
    assert.throws(() =>
      ConvertLeadToProspectInputSchema.parse({ leadId: LEAD_ID, legalName: "", actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
    );
  });
});

describe("ConversionReadinessSchema", () => {
  test("accepts the shape app.get_prospect_conversion_readiness returns", () => {
    const parsed = ConversionReadinessSchema.parse({ ready: false, missing: ["tax_id", "billing_address"] });
    assert.equal(parsed.ready, false);
    assert.equal(parsed.missing.length, 2);
  });
});

describe("parseProspect", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const prospect = parseProspect({
      id: PROSPECT_ID,
      tenant_id: TENANT_ID,
      lead_id: LEAD_ID,
      legal_name: "Contoso Ltd",
      trade_name: "Contoso",
      tax_id: "01.234.567.8-901.000",
      billing_address: { city: "Jakarta" },
      contact_name: "Jane Doe",
      contact_email: "jane@contoso.test",
      contact_phone: null,
      status: "active",
      disqualify_reason: null,
      owner_user_id: ACTOR_ID,
      org_unit_id: null,
      merged_into_id: null,
      merged_at: null,
      merged_by: null,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
      updated_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(prospect.status, "active");
    assert.equal(prospect.leadId, LEAD_ID);
    assert.equal(prospect.legalName, "Contoso Ltd");
  });
});
