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
  listCustomerAccountsForActor,
  listCustomerTicketCategories,
  getCustomerTicket,
  listCustomerTickets,
  listCustomerTicketMessages,
  listHelpdeskTicketCategories,
  getTenantHelpdeskTicket,
  listTenantHelpdeskTickets,
  listTenantHelpdeskTicketMessages,
  listSupportQueues,
  listPlatformHelpdeskTickets,
  getPlatformHelpdeskTicket,
  listSlaPolicies,
  listSlaPolicyVersions,
  getTicketSlaClock,
  getTicketSlaStatusForRequester,
  listTicketSlaClockEvents,
  listTicketRoutingRules,
  listTicketRoutingRuleVersions,
  previewTicketRouting,
  listTicketAssignmentCandidates,
  getTicketQueueWorkload,
  listTicketAssignmentEvents,
  TicketQueryError,
  type TicketQueryClient,
} from "./ticketing.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "523e4567-e89b-12d3-a456-426614174000";
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

describe("HRT-287 (CG-S12-HRT-015): customer-facing read queries", () => {
  test("listCustomerAccountsForActor calls the dedicated RPC, never the internal account listing", async () => {
    const { client, calls } = fakeClient({ data: [{ account_id: ID_1, legal_name: "Acme Logistics", parent_account_id: null }], error: null });
    const rows = await listCustomerAccountsForActor(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_customer_accounts_for_actor");
    assert.equal(rows[0]?.legalName, "Acme Logistics");
  });

  test("listCustomerTicketCategories calls the dedicated RPC", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listCustomerTicketCategories(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_customer_ticket_categories");
  });

  test("getCustomerTicket returns null on zero rows -- indistinguishable from a nonexistent, cross-account, or internal-channel ticket id", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getCustomerTicket(client, ID_1, ACTOR_ID);
    assert.equal(result, null);
  });

  test("listCustomerTickets forwards the optional account filter, defaults limit to 50", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listCustomerTickets(client, TENANT_ID, ACTOR_ID, { accountId: ID_1, status: "open" });
    assert.equal(calls[0]?.args.p_account_id, ID_1);
    assert.equal(calls[0]?.args.p_limit, 50);
  });

  test("listCustomerTicketMessages calls the dedicated RPC, defaults limit to 100 -- no visibility parameter exists to forward", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listCustomerTicketMessages(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_customer_ticket_messages");
    assert.equal(calls[0]?.args.p_limit, 100);
    assert.equal((calls[0]?.args as Record<string, unknown>).p_visibility, undefined);
  });
});

describe("HRT-288 (CG-S12-HRT-016): tenant-side helpdesk read queries", () => {
  test("listHelpdeskTicketCategories calls the dedicated RPC", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listHelpdeskTicketCategories(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_helpdesk_ticket_categories");
  });

  test("getTenantHelpdeskTicket returns null on zero rows -- indistinguishable from a nonexistent, cross-tenant, or non-helpdesk-channel ticket id", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getTenantHelpdeskTicket(client, ID_1, ACTOR_ID);
    assert.equal(result, null);
  });

  test("listTenantHelpdeskTickets defaults limit to 50 and forwards status", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTenantHelpdeskTickets(client, TENANT_ID, ACTOR_ID, { status: "open" });
    assert.equal(calls[0]?.args.p_status, "open");
    assert.equal(calls[0]?.args.p_limit, 50);
  });

  test("listTenantHelpdeskTicketMessages calls the dedicated RPC, no visibility parameter exists to forward", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listTenantHelpdeskTicketMessages(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_tenant_helpdesk_ticket_messages");
    assert.equal((calls[0]?.args as Record<string, unknown>).p_visibility, undefined);
  });
});

describe("HRT-288: Platform-side (Supreme-Admin-facing) helpdesk read queries", () => {
  test("listSupportQueues calls the dedicated RPC", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listSupportQueues(client, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_support_queues");
    assert.deepEqual(calls[0]?.args, { p_actor_auth_user_id: ACTOR_ID });
  });

  test("listPlatformHelpdeskTickets never requires a tenantId -- the one deliberate cross-tenant read this capability introduces", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listPlatformHelpdeskTickets(client, ACTOR_ID, { severity: "high" });
    assert.equal(calls[0]?.fn, "list_platform_helpdesk_tickets");
    assert.equal(calls[0]?.args.p_tenant_id, null);
    assert.equal(calls[0]?.args.p_severity, "high");
  });

  test("getPlatformHelpdeskTicket returns null on zero rows", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getPlatformHelpdeskTicket(client, ID_1, ACTOR_ID);
    assert.equal(result, null);
  });
});

describe("HRT-289 SLA read queries", () => {
  test("listSlaPolicies passes tenant/actor through", async () => {
    const { client, calls } = fakeClient({ data: [{ id: ID_1, code: "NARROW", name: "Narrow", status: "active", record_version: 1 }], error: null });
    const result = await listSlaPolicies(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(result[0]?.code, "NARROW");
  });

  test("listSlaPolicyVersions parses scope/target fields", async () => {
    const { client } = fakeClient({
      data: [{
        id: ID_1, version_number: 1, status: "published", channel: "internal", category_id: null, priority: null,
        customer_account_id: null, queue_id: null, support_queue_id: null, calendar_id: ID_2,
        response_target_minutes: 60, resolution_target_minutes: 480, precedence_rank: 0, published_at: null, record_version: 1,
      }],
      error: null,
    });
    const result = await listSlaPolicyVersions(client, ID_1, ACTOR_ID);
    assert.equal(result[0]?.responseTargetMinutes, 60);
  });

  test("getTicketSlaClock returns null on zero rows (non-staff caller)", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getTicketSlaClock(client, ID_1, ACTOR_ID);
    assert.equal(result, null);
  });

  test("getTicketSlaStatusForRequester calls the narrower requester-safe RPC, distinct from getTicketSlaClock", async () => {
    const { client, calls } = fakeClient({ data: [{ ticket_id: ID_1, response_target_minutes: 60, response_status: "pending", resolution_target_minutes: 480, resolution_status: "pending" }], error: null });
    const result = await getTicketSlaStatusForRequester(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_ticket_sla_status_for_requester");
    assert.equal(result?.responseStatus, "pending");
  });

  test("listTicketSlaClockEvents throws TicketQueryError on RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => listTicketSlaClockEvents(client, ID_1, ACTOR_ID), TicketQueryError);
  });
});

describe("HRT-290 (CG-S12-HRT-018) ticket assignment read queries", () => {
  test("listTicketRoutingRules / listTicketRoutingRuleVersions parse the scope/target tuple", async () => {
    const { client: rulesClient } = fakeClient({ data: [{ id: ID_1, code: "GEN-ROUTE", name: "General", status: "active", record_version: 1 }], error: null });
    const rules = await listTicketRoutingRules(rulesClient, TENANT_ID, ACTOR_ID);
    assert.equal(rules[0]?.code, "GEN-ROUTE");

    const { client: versionsClient } = fakeClient({
      data: [{
        id: ID_1, version_number: 2, status: "published", channel: "internal", category_id: ID_2, priority: null,
        target_queue_id: ID_1, assignment_mode: "least_loaded", max_active_assignments_per_member: 3,
        precedence_rank: 0, published_at: "2026-08-01T00:00:00Z", record_version: 1,
      }],
      error: null,
    });
    const versions = await listTicketRoutingRuleVersions(versionsClient, ID_1, ACTOR_ID);
    assert.equal(versions[0]?.assignmentMode, "least_loaded");
    assert.equal(versions[0]?.maxActiveAssignmentsPerMember, 3);
  });

  test("previewTicketRouting returns null on zero rows, and parses a matched=false row without a hard error", async () => {
    const { client: empty } = fakeClient({ data: [], error: null });
    const emptyResult = await previewTicketRouting(empty, TENANT_ID, "internal", ID_1, "normal", ACTOR_ID);
    assert.equal(emptyResult, null);

    const { client: noMatch } = fakeClient({
      data: [{ matched: false, rule_id: null, rule_version_id: null, version_number: null, target_queue_id: null, target_queue_code: null, assignment_mode: null, max_active_assignments_per_member: null }],
      error: null,
    });
    const noMatchResult = await previewTicketRouting(noMatch, TENANT_ID, "internal", ID_1, "normal", ACTOR_ID);
    assert.equal(noMatchResult?.matched, false);
  });

  test("listTicketAssignmentCandidates parses eligibility/workload fields, never a raw employee directory shape", async () => {
    const { client } = fakeClient({
      data: [{ employee_id: ID_1, employee_name: "Staff One", is_eligible: true, active_ticket_count: 1, ineligible_reason: null }],
      error: null,
    });
    const result = await listTicketAssignmentCandidates(client, ID_1, ACTOR_ID);
    assert.equal(result[0]?.employeeName, "Staff One");
    assert.equal(result[0]?.isEligible, true);
  });

  test("getTicketQueueWorkload is a read-only aggregation query", async () => {
    const { client, calls } = fakeClient({ data: [{ employee_id: ID_1, employee_name: "Staff One", active_ticket_count: 2, is_eligible: true }], error: null });
    const result = await getTicketQueueWorkload(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.fn, "get_ticket_queue_workload");
    assert.equal(result[0]?.activeTicketCount, 2);
  });

  test("listTicketAssignmentEvents parses the ledger row shape including source/rule_version_id", async () => {
    const { client } = fakeClient({
      data: [{
        id: ID_1, event_type: "claim", source: "claim", rule_version_id: null,
        from_assignee_employee_id: null, from_assignee_name: null, to_assignee_employee_id: ID_2, to_assignee_name: "Staff One",
        from_queue_id: null, to_queue_id: null, reason: null, actor_label: "staff1", occurred_at: "2026-08-01T00:00:00Z",
      }],
      error: null,
    });
    const result = await listTicketAssignmentEvents(client, ID_1, ACTOR_ID);
    assert.equal(result[0]?.eventType, "claim");
    assert.equal(result[0]?.toAssigneeName, "Staff One");
  });

  test("listTicketAssignmentEvents throws TicketQueryError on RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => listTicketAssignmentEvents(client, ID_1, ACTOR_ID), TicketQueryError);
  });
});
