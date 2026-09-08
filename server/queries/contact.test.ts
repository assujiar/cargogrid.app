import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { findDuplicateContacts, listContacts, getContactById, listActivitiesForRecord, ContactQueryError, type ContactQueryRpcClient } from "./contact.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONTACT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTIVITY_ID = "423e4567-e89b-12d3-a456-426614174000";
const LEAD_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

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

const VALID_ACTIVITY_ROW = {
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
};

describe("findDuplicateContacts", () => {
  test("calls find_duplicate_contacts with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: [VALID_CONTACT_ROW], error: null };
      },
    } as unknown as ContactQueryRpcClient;
    const contacts = await findDuplicateContacts(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, email: "budi@contoso.test" });

    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_email: "budi@contoso.test", p_phone: null });
    assert.equal(contacts.length, 1);
  });

  test("wraps a query error", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "insufficient_authority: identity x holds no active membership" } };
      },
    } as unknown as ContactQueryRpcClient;
    await assert.rejects(
      () => findDuplicateContacts(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof ContactQueryError);
        return true;
      },
    );
  });
});

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: { fn: string; args: Record<string, unknown> }[] }): ContactQueryRpcClient {
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture.calls.push({ fn, args });
      return response;
    },
  };
  return fake as unknown as ContactQueryRpcClient;
}

describe("listContacts", () => {
  test("calls list_contacts with tenant/actor/page/pageSize and maps total_count", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ data: [{ ...VALID_CONTACT_ROW, total_count: 1 }], error: null }, capture);

    const result = await listContacts(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 });
    assert.equal(capture.calls[0]?.fn, "list_contacts");
    assert.deepEqual(capture.calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_page: 1, p_page_size: 50 });
    assert.equal(result.contacts.length, 1);
    assert.equal(result.totalCount, 1);
  });
});

describe("getContactById", () => {
  test("returns the parsed contact when found", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ data: [VALID_CONTACT_ROW], error: null }, capture);
    const contact = await getContactById(client, CONTACT_ID, ACTOR_ID);
    assert.equal(contact?.id, CONTACT_ID);
  });

  test("returns null (never an error) when denied/no-match yields zero rows", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ data: [], error: null }, capture);
    const contact = await getContactById(client, CONTACT_ID, ACTOR_ID);
    assert.equal(contact, null);
  });
});

describe("listActivitiesForRecord", () => {
  test("calls list_activities_for_record with related_type/related_id/actor", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ data: [VALID_ACTIVITY_ROW], error: null }, capture);
    const activities = await listActivitiesForRecord(client, "lead", LEAD_ID, ACTOR_ID);
    assert.equal(capture.calls[0]?.fn, "list_activities_for_record");
    assert.deepEqual(capture.calls[0]?.args, { p_related_type: "lead", p_related_id: LEAD_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(activities.length, 1);
  });
});
