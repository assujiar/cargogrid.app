import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { CreateContactInputSchema, LogActivityInputSchema, parseContact, parseContactLink, parseActivity } from "./contact.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONTACT_ID = "323e4567-e89b-12d3-a456-426614174000";
const LINK_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTIVITY_ID = "523e4567-e89b-12d3-a456-426614174000";
const LEAD_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("CreateContactInputSchema", () => {
  test("applies defaults for omitted optional fields", () => {
    const parsed = CreateContactInputSchema.parse({ tenantId: TENANT_ID, fullName: "Budi Santoso", actorAuthUserId: ACTOR_ID, createdBy: "tester" });
    assert.equal(parsed.title, null);
    assert.equal(parsed.email, null);
  });

  test("rejects a malformed email", () => {
    assert.throws(() =>
      CreateContactInputSchema.parse({ tenantId: TENANT_ID, fullName: "Budi Santoso", email: "not-an-email", actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
    );
  });
});

describe("LogActivityInputSchema", () => {
  test("defaults status to scheduled", () => {
    const parsed = LogActivityInputSchema.parse({ relatedType: "lead", relatedId: LEAD_ID, type: "task", subject: "Follow up", actorAuthUserId: ACTOR_ID, createdBy: "tester" });
    assert.equal(parsed.status, "scheduled");
  });

  test("rejects an unknown activity type", () => {
    assert.throws(() =>
      LogActivityInputSchema.parse({ relatedType: "lead", relatedId: LEAD_ID, type: "fax", subject: "x", actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
    );
  });
});

describe("parseContact", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const contact = parseContact({
      id: CONTACT_ID,
      tenant_id: TENANT_ID,
      full_name: "Budi Santoso",
      title: "Procurement Manager",
      email: "budi@contoso.test",
      phone: null,
      status: "active",
      owner_user_id: ACTOR_ID,
      org_unit_id: null,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
      updated_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(contact.fullName, "Budi Santoso");
    assert.equal(contact.status, "active");
  });
});

describe("parseContactLink", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const link = parseContactLink({
      id: LINK_ID,
      tenant_id: TENANT_ID,
      contact_id: CONTACT_ID,
      related_type: "lead",
      related_id: LEAD_ID,
      role: "decision_maker",
      is_primary: true,
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(link.role, "decision_maker");
    assert.equal(link.isPrimary, true);
  });
});

describe("parseActivity", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const activity = parseActivity({
      id: ACTIVITY_ID,
      tenant_id: TENANT_ID,
      type: "call",
      subject: "Intro call",
      notes: null,
      status: "completed",
      due_at: null,
      completed_at: "2026-07-23T00:00:00.000Z",
      outcome: "Positive",
      related_type: "lead",
      related_id: LEAD_ID,
      contact_id: CONTACT_ID,
      owner_user_id: ACTOR_ID,
      org_unit_id: null,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
      updated_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(activity.type, "call");
    assert.equal(activity.status, "completed");
  });
});
