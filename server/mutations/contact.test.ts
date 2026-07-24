import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createContact,
  linkContactToRecord,
  unlinkContactFromRecord,
  logActivity,
  completeActivity,
  rescheduleActivity,
  cancelActivity,
  ContactMutationError,
  type ContactMutationRpcClient,
} from "./contact.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONTACT_ID = "323e4567-e89b-12d3-a456-426614174000";
const LINK_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTIVITY_ID = "523e4567-e89b-12d3-a456-426614174000";
const LEAD_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

const VALID_CONTACT_ROW = {
  id: CONTACT_ID,
  tenant_id: TENANT_ID,
  full_name: "Budi Santoso",
  title: null,
  email: "budi@contoso.test",
  phone: null,
  status: "active",
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

const VALID_LINK_ROW = {
  id: LINK_ID,
  tenant_id: TENANT_ID,
  contact_id: CONTACT_ID,
  related_type: "lead",
  related_id: LEAD_ID,
  role: "decision_maker",
  is_primary: true,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
};

const VALID_ACTIVITY_ROW = {
  id: ACTIVITY_ID,
  tenant_id: TENANT_ID,
  type: "call",
  subject: "Intro call",
  notes: null,
  status: "scheduled",
  due_at: "2026-07-24T00:00:00.000Z",
  completed_at: null,
  outcome: null,
  related_type: "lead",
  related_id: LEAD_ID,
  contact_id: CONTACT_ID,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): ContactMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  };
  return Object.assign(fake as unknown as ContactMutationRpcClient, { calls });
}

describe("createContact", () => {
  test("calls create_contact with the exact snake_case params and defaults applied", async () => {
    const client = fakeClient({ data: VALID_CONTACT_ROW, error: null });
    await createContact(client, { tenantId: TENANT_ID, fullName: "Budi Santoso", email: "budi@contoso.test", actorAuthUserId: ACTOR_ID, createdBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_full_name: "Budi Santoso",
      p_title: null,
      p_email: "budi@contoso.test",
      p_phone: null,
      p_owner_user_id: null,
      p_org_unit_id: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "tester",
    });
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x holds no active membership for tenant y" } });
    await assert.rejects(
      () => createContact(client, { tenantId: TENANT_ID, fullName: "Budi Santoso", email: "budi@contoso.test", actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ContactMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("linkContactToRecord", () => {
  test("calls link_contact_to_record with the exact snake_case params and defaults applied", async () => {
    const client = fakeClient({ data: VALID_LINK_ROW, error: null });
    await linkContactToRecord(client, { contactId: CONTACT_ID, relatedType: "lead", relatedId: LEAD_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_contact_id: CONTACT_ID,
      p_related_type: "lead",
      p_related_id: LEAD_ID,
      p_role: "other",
      p_is_primary: false,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tester",
    });
  });

  test("wraps a cross_tenant_link_denied error", async () => {
    const client = fakeClient({ data: null, error: { message: "cross_tenant_link_denied: contact and record belong to different tenants" } });
    await assert.rejects(
      () => linkContactToRecord(client, { contactId: CONTACT_ID, relatedType: "lead", relatedId: LEAD_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ContactMutationError);
        assert.equal(err.code, "cross_tenant_link_denied");
        return true;
      },
    );
  });
});

describe("unlinkContactFromRecord", () => {
  test("calls unlink_contact_from_record with the exact snake_case params", async () => {
    const client = fakeClient({ data: null, error: null });
    await unlinkContactFromRecord(client, { linkId: LINK_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.deepEqual(client.calls[0]?.args, { p_link_id: LINK_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester" });
  });
});

describe("logActivity", () => {
  test("calls log_activity with the exact snake_case params and defaults applied", async () => {
    const client = fakeClient({ data: VALID_ACTIVITY_ROW, error: null });
    await logActivity(client, { relatedType: "lead", relatedId: LEAD_ID, type: "call", subject: "Intro call", actorAuthUserId: ACTOR_ID, createdBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_related_type: "lead",
      p_related_id: LEAD_ID,
      p_contact_id: null,
      p_type: "call",
      p_subject: "Intro call",
      p_notes: null,
      p_status: "scheduled",
      p_due_at: null,
      p_completed_at: null,
      p_outcome: null,
      p_owner_user_id: null,
      p_org_unit_id: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "tester",
    });
  });

  test("wraps a related_record_not_found error", async () => {
    const client = fakeClient({ data: null, error: { message: "related_record_not_found: lead x" } });
    await assert.rejects(
      () => logActivity(client, { relatedType: "lead", relatedId: LEAD_ID, type: "call", subject: "x", actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ContactMutationError);
        assert.equal(err.code, "related_record_not_found");
        return true;
      },
    );
  });
});

describe("completeActivity", () => {
  test("calls complete_activity with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_ACTIVITY_ROW, status: "completed", completed_at: "2026-07-23T00:00:00.000Z" }, error: null });
    const activity = await completeActivity(client, { activityId: ACTIVITY_ID, expectedVersion: 1, outcome: "Positive", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(activity.status, "completed");
  });

  test("wraps an invalid_transition error", async () => {
    const client = fakeClient({ data: null, error: { message: "invalid_transition: activity x is completed and cannot be completed" } });
    await assert.rejects(
      () => completeActivity(client, { activityId: ACTIVITY_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ContactMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("rescheduleActivity", () => {
  test("calls reschedule_activity with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_ACTIVITY_ROW, due_at: "2026-08-01T00:00:00.000Z", record_version: 2 }, error: null });
    const activity = await rescheduleActivity(client, { activityId: ACTIVITY_ID, expectedVersion: 1, newDueAt: "2026-08-01T00:00:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(activity.recordVersion, 2);
  });

  test("wraps a stale_version error", async () => {
    const client = fakeClient({ data: null, error: { message: "stale_version: activity x expected version 1 but found 2" } });
    await assert.rejects(
      () => rescheduleActivity(client, { activityId: ACTIVITY_ID, expectedVersion: 1, newDueAt: "2026-08-01T00:00:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ContactMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("cancelActivity", () => {
  test("calls cancel_activity with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_ACTIVITY_ROW, status: "cancelled" }, error: null });
    const activity = await cancelActivity(client, { activityId: ACTIVITY_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(activity.status, "cancelled");
  });
});
