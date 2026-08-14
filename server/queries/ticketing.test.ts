import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listTicketQueues,
  listTicketCategories,
  listTicketQueueMembers,
  getTicket,
  listTickets,
  listMyTickets,
  listTicketMessages,
  listTicketWatchers,
  listTicketEvents,
  exportTickets,
  TicketQueryError,
  type TicketQueryClient,
} from "./ticketing.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: TicketQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TicketQueryClient;
  return { client, calls };
}

describe("listTicketQueues / listTicketCategories / listTicketQueueMembers", () => {
  test("listTicketQueues passes tenant/actor through and parses rows", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, org_unit_id: ID_1, code: "IT", name: "IT Support", description: null, status: "active", record_version: 1 }], error: null });
    const rows = await listTicketQueues(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(rows[0]?.code, "IT");
  });

  test("listTicketCategories throws TicketQueryError on RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => listTicketCategories(client, TENANT_ID, ACTOR_ID), TicketQueryError);
  });

  test("listTicketQueueMembers passes queue/actor through", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTicketQueueMembers(client, ID_1, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_queue_id: ID_1, p_actor_auth_user_id: ACTOR_ID });
  });
});

describe("getTicket / listTickets / listMyTickets", () => {
  test("getTicket returns null when the RPC returns zero rows (cross-tenant/no-access case)", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getTicket(client, ID_1, ACTOR_ID);
    assert.equal(result, null);
  });

  test("listTickets defaults limit to 50 and forwards every filter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTickets(client, TENANT_ID, ACTOR_ID, { status: "open", queueId: ID_1, categoryId: null, priority: "high", assigneeEmployeeId: null, afterId: null });
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.args.p_status, "open");
    assert.equal(calls[0]?.args.p_priority, "high");
  });

  test("listMyTickets omits queue/category/assignee filters (self-scoped, requester resolved server-side)", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listMyTickets(client, TENANT_ID, ACTOR_ID, { status: null });
    assert.deepEqual(Object.keys(calls[0]?.args ?? {}).sort(), ["p_actor_auth_user_id", "p_after_id", "p_limit", "p_status", "p_tenant_id"]);
  });
});

describe("listTicketMessages / listTicketWatchers / listTicketEvents / exportTickets", () => {
  test("listTicketMessages defaults limit to 100 (a conversation thread, not a summary list)", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTicketMessages(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.args.p_limit, 100);
  });

  test("listTicketWatchers/listTicketEvents pass ticket/actor through", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTicketWatchers(client, ID_1, ACTOR_ID);
    await listTicketEvents(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_ticket_watchers");
    assert.equal(calls[1]?.fn, "list_ticket_events");
  });

  test("exportTickets forwards the date range unchanged", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await exportTickets(client, TENANT_ID, ACTOR_ID, "2026-01-01", "2026-06-30");
    assert.equal(calls[0]?.args.p_from_date, "2026-01-01");
    assert.equal(calls[0]?.args.p_to_date, "2026-06-30");
  });
});
