import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { findDuplicateContacts, listContacts, getContactById, listActivitiesForRecord, ContactQueryError, type ContactQueryRpcClient } from "./contact.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

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

function fakeTableClient(response: { data: unknown; error: { message: string } | null; count?: number }, capture: { calls: Record<string, unknown> }): Pick<SupabaseClient, "from"> {
  const fake = {
    from(table: string) {
      capture.calls.table = table;
      return {
        select(columns: string, options?: { count?: string }) {
          capture.calls.columns = columns;
          capture.calls.countOption = options?.count;
          return {
            eq(column: string, value: unknown) {
              const eqCalls = (capture.calls.eq as { column: string; value: unknown }[] | undefined) ?? [];
              eqCalls.push({ column, value });
              capture.calls.eq = eqCalls;
              return {
                eq(column2: string, value2: unknown) {
                  eqCalls.push({ column: column2, value: value2 });
                  return {
                    order(column3: string, opts: { ascending: boolean }) {
                      capture.calls.orderColumn = column3;
                      capture.calls.ascending = opts.ascending;
                      return response;
                    },
                  };
                },
                order(column2: string, opts: { ascending: boolean }) {
                  capture.calls.orderColumn = column2;
                  capture.calls.ascending = opts.ascending;
                  return {
                    async range(from: number, to: number) {
                      capture.calls.from = from;
                      capture.calls.to = to;
                      return response;
                    },
                  };
                },
                async maybeSingle() {
                  const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
                  return { data: row, error: response.error };
                },
              };
            },
          };
        },
      };
    },
  };
  return fake as unknown as Pick<SupabaseClient, "from">;
}

describe("listContacts", () => {
  test("bounds the query to one 50-row default page, ordered by full_name ascending", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_CONTACT_ROW], error: null, count: 1 }, capture);

    const result = await listContacts(client, { tenantId: TENANT_ID, page: 1 });
    assert.equal(capture.calls.table, "contacts");
    assert.equal(capture.calls.orderColumn, "full_name");
    assert.equal(capture.calls.ascending, true);
    assert.equal(capture.calls.from, 0);
    assert.equal(capture.calls.to, 49);
    assert.equal(result.contacts.length, 1);
  });
});

describe("getContactById", () => {
  test("returns the parsed contact when found", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_CONTACT_ROW], error: null }, capture);
    const contact = await getContactById(client, CONTACT_ID);
    assert.equal(contact?.id, CONTACT_ID);
  });

  test("returns null (never an error) when RLS/no-match yields zero rows", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);
    const contact = await getContactById(client, CONTACT_ID);
    assert.equal(contact, null);
  });
});

describe("listActivitiesForRecord", () => {
  test("filters by related_type/related_id and orders newest first", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_ACTIVITY_ROW], error: null }, capture);
    const activities = await listActivitiesForRecord(client, "lead", LEAD_ID);
    assert.equal(capture.calls.table, "activities");
    assert.equal(capture.calls.orderColumn, "created_at");
    assert.equal(capture.calls.ascending, false);
    assert.equal(activities.length, 1);
  });
});
