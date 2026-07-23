import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { CaptureLeadInputSchema, LeadScoreExplanationSchema, parseLead } from "./lead.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEAD_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("CaptureLeadInputSchema", () => {
  test("requires either email or contact identifiers to be present -- but schema-level only allows both null (DB-level CHECK is the real gate)", () => {
    const parsed = CaptureLeadInputSchema.parse({
      tenantId: TENANT_ID,
      source: "manual",
      contactName: "Jane Doe",
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });
    assert.equal(parsed.source, "manual");
    assert.equal(parsed.externalReference, null);
  });

  test("rejects an unknown source", () => {
    assert.throws(() =>
      CaptureLeadInputSchema.parse({
        tenantId: TENANT_ID,
        source: "cold-call",
        contactName: "Jane Doe",
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
  });

  test("rejects a malformed email", () => {
    assert.throws(() =>
      CaptureLeadInputSchema.parse({
        tenantId: TENANT_ID,
        source: "manual",
        contactName: "Jane Doe",
        email: "not-an-email",
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
  });
});

describe("LeadScoreExplanationSchema", () => {
  test("accepts the shape app.compute_lead_score returns", () => {
    const parsed = LeadScoreExplanationSchema.parse({
      version: 1,
      rules: [{ rule: "has_email", points: 20 }],
    });
    assert.equal(parsed.rules.length, 1);
  });
});

describe("parseLead", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const lead = parseLead({
      id: LEAD_ID,
      tenant_id: TENANT_ID,
      source: "manual",
      external_reference: null,
      company_name: "Contoso Ltd",
      contact_name: "Jane Doe",
      email: "jane@contoso.test",
      phone: null,
      duplicate_fingerprint: "abc123",
      status: "new",
      disqualify_reason: null,
      score: 20,
      score_explanation: { version: 1, rules: [{ rule: "has_email", points: 20 }] },
      score_version: 1,
      owner_user_id: ACTOR_ID,
      org_unit_id: null,
      assigned_at: null,
      assigned_by: null,
      qualified_at: null,
      disqualified_at: null,
      merged_into_id: null,
      merged_at: null,
      merged_by: null,
      converted_at: null,
      last_activity_at: "2026-07-23T00:00:00.000Z",
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
      updated_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(lead.status, "new");
    assert.equal(lead.ownerUserId, ACTOR_ID);
    assert.equal(lead.score, 20);
  });
});
