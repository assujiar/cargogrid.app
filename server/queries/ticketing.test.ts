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
  listCustomerTicketLinks,
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
  listTicketEscalationPolicies,
  listTicketEscalationPolicyVersions,
  listTicketEscalationLevels,
  previewTicketEscalation,
  getTicketEscalation,
  getTicketEscalationStatusForRequester,
  listTicketEscalationEvents,
  listTicketEscalationSuppressions,
  listTicketBreachQueue,
  searchTicketLinkCandidates,
  listTicketLinks,
  listTicketLinkEvents,
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

  // HRT-295 (ISS-2026-110 fix): listCustomerTicketLinks calls the dedicated
  // customer-safe RPC, never listTicketLinks -- and parses a genericized
  // created_by exactly like any other TicketLinkRow column (the
  // genericization itself is proven live at the database layer by
  // scripts/db-tests/ticketing-linked-records.sql; this unit test proves
  // the TS wrapper calls the right RPC and does not re-raw the value).
  test("listCustomerTicketLinks calls the dedicated RPC, never list_ticket_links", async () => {
    const { client, calls } = fakeClient({
      data: [{
        id: ID_1, entity_type: "shipment", entity_id: ID_2, relationship: "primary_subject", status: "active",
        live_available: true, label: "SHP-0001", detail: "confirmed", status_label: "confirmed",
        linked_at: "2026-08-01T00:00:00Z", created_by: "Support Team", record_version: 1,
      }],
      error: null,
    });
    const result = await listCustomerTicketLinks(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_customer_ticket_links");
    assert.deepEqual(calls[0]?.args, { p_ticket_id: ID_1, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(result[0]?.createdBy, "Support Team");
  });

  test("listCustomerTicketLinks throws TicketQueryError on RPC error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "ticket_not_found: x" } });
    await assert.rejects(() => listCustomerTicketLinks(client, ID_1, ACTOR_ID), TicketQueryError);
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

describe("HRT-291 (CG-S12-HRT-019) ticket escalation read queries", () => {
  test("listTicketEscalationPolicies / listTicketEscalationPolicyVersions / listTicketEscalationLevels parse their own row shapes", async () => {
    const { client: policiesClient } = fakeClient({ data: [{ id: ID_1, code: "GEN-ESC", name: "General escalation", status: "active", record_version: 1 }], error: null });
    const policies = await listTicketEscalationPolicies(policiesClient, TENANT_ID, ACTOR_ID);
    assert.equal(policies[0]?.code, "GEN-ESC");

    const { client: versionsClient } = fakeClient({
      data: [{ id: ID_1, version_number: 1, status: "published", channel: "internal", category_id: ID_2, priority: null, queue_id: ID_1, precedence_rank: 0, published_at: "2026-08-01T00:00:00Z", record_version: 1 }],
      error: null,
    });
    const versions = await listTicketEscalationPolicyVersions(versionsClient, ID_1, ACTOR_ID);
    assert.equal(versions[0]?.channel, "internal");

    const { client: levelsClient } = fakeClient({
      data: [{
        id: ID_1, level_number: 1, trigger_type: "inactivity", threshold_minutes: 30, min_priority: null,
        target_type: "employee", target_queue_id: null, target_queue_code: null, target_employee_id: ID_2, target_employee_name: "Staff One",
        action_notify: true, action_reassign: false, cooldown_minutes: 60,
      }],
      error: null,
    });
    const levels = await listTicketEscalationLevels(levelsClient, ID_1, ACTOR_ID);
    assert.equal(levels[0]?.triggerType, "inactivity");
    assert.equal(levels[0]?.thresholdMinutes, 30);
  });

  test("previewTicketEscalation returns null when the RPC returns zero rows", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    const result = await previewTicketEscalation(client, TENANT_ID, "internal", null, null, null, ACTOR_ID);
    assert.equal(result, null);
    assert.equal(calls[0]?.fn, "preview_ticket_escalation");
  });

  test("getTicketEscalation (staff-only) and getTicketEscalationStatusForRequester (customer-safe) call DIFFERENT RPCs and never share a projection", async () => {
    const { client: staffClient, calls: staffCalls } = fakeClient({
      data: [{
        id: ID_1, policy_version_id: ID_2, status: "active", current_level: 1, current_level_id: ID_1,
        last_trigger_type: "manual", acknowledged_at: null, acknowledged_by: null, resolved_at: null, resolved_reason: null,
        last_triggered_at: "2026-08-01T00:00:00Z", record_version: 1,
      }],
      error: null,
    });
    const staffRow = await getTicketEscalation(staffClient, ID_1, ACTOR_ID);
    assert.equal(staffCalls[0]?.fn, "get_ticket_escalation");
    assert.equal(staffRow?.currentLevel, 1);

    const { client: requesterClient, calls: requesterCalls } = fakeClient({ data: [{ is_escalated: true }], error: null });
    const requesterRow = await getTicketEscalationStatusForRequester(requesterClient, ID_1, ACTOR_ID);
    assert.equal(requesterCalls[0]?.fn, "get_ticket_escalation_status_for_requester");
    assert.equal(requesterRow?.isEscalated, true);
    assert.equal(Object.keys(requesterRow ?? {}).length, 1);
  });

  test("listTicketEscalationEvents / listTicketEscalationSuppressions throw TicketQueryError on RPC error", async () => {
    const { client: eventsClient } = fakeClient({ data: null, error: { message: "ticket_not_found: x" } });
    await assert.rejects(() => listTicketEscalationEvents(eventsClient, ID_1, ACTOR_ID), TicketQueryError);

    const { client: suppressionsClient } = fakeClient({ data: null, error: { message: "channel_not_supported: x" } });
    await assert.rejects(() => listTicketEscalationSuppressions(suppressionsClient, ID_1, ACTOR_ID), TicketQueryError);
  });

  test("listTicketBreachQueue is the dedicated breach/stuck-queue browser, cursor-paginated", async () => {
    const { client, calls } = fakeClient({
      data: [{
        ticket_id: ID_1, ticket_number: "TKT-2026-000001", subject: "Stuck ticket", status: "open", priority: "urgent",
        queue_code: "SUP", current_level: 2, last_trigger_type: "inactivity", escalation_status: "active",
        last_triggered_at: "2026-08-01T00:00:00Z", acknowledged_at: null,
      }],
      error: null,
    });
    const result = await listTicketBreachQueue(client, TENANT_ID, ACTOR_ID, { minLevel: 1, limit: 25 });
    assert.equal(calls[0]?.fn, "list_ticket_breach_queue");
    assert.equal(calls[0]?.args.p_min_level, 1);
    assert.equal(result[0]?.currentLevel, 2);
  });
});

describe("HRT-292 (CG-S12-HRT-020): Typed Ticket-Linked Records reads", () => {
  test("searchTicketLinkCandidates passes ticket/entityType/search/limit through and parses rows", async () => {
    const { client, calls } = fakeClient({
      data: [{ entity_id: ID_1, primary_label: "SHP-2026-0001", secondary_label: "sea / FCL", status_label: "confirmed" }],
      error: null,
    });
    const result = await searchTicketLinkCandidates(client, ID_1, "shipment", "SHP", ACTOR_ID, 10);
    assert.equal(calls[0]?.fn, "search_ticket_link_candidates");
    assert.deepEqual(calls[0]?.args, { p_ticket_id: ID_1, p_entity_type: "shipment", p_search_text: "SHP", p_actor_auth_user_id: ACTOR_ID, p_limit: 10 });
    assert.equal(result[0]?.primaryLabel, "SHP-2026-0001");
  });

  test("searchTicketLinkCandidates defaults limit to 20 when omitted", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await searchTicketLinkCandidates(client, ID_1, "warehouse", null, ACTOR_ID);
    assert.equal(calls[0]?.args.p_limit, 20);
  });

  test("searchTicketLinkCandidates throws TicketQueryError on RPC error (e.g. unsupported_entity_type)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "unsupported_entity_type: purchase_order" } });
    await assert.rejects(() => searchTicketLinkCandidates(client, ID_1, "shipment", null, ACTOR_ID), TicketQueryError);
  });

  test("listTicketLinks parses a live-available and an unavailable row in the same call", async () => {
    const { client, calls } = fakeClient({
      data: [
        {
          id: ID_1, entity_type: "invoice", entity_id: ID_2, relationship: "primary_subject", status: "active",
          live_available: true, label: "INV-2026-0001", detail: "USD 1100.00", status_label: "approved",
          linked_at: "2026-08-01T00:00:00Z", created_by: "admin", record_version: 1,
        },
        {
          id: ID_2, entity_type: "warehouse", entity_id: ID_1, relationship: "related", status: "active",
          live_available: false, label: null, detail: null, status_label: "unavailable",
          linked_at: "2026-08-01T00:00:00Z", created_by: "admin", record_version: 1,
        },
      ],
      error: null,
    });
    const result = await listTicketLinks(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_ticket_links");
    assert.equal(result[0]?.liveAvailable, true);
    assert.equal(result[1]?.liveAvailable, false);
    assert.equal(result[1]?.label, null);
  });

  test("listTicketLinks throws TicketQueryError on RPC error (e.g. ticket_not_found)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "ticket_not_found: x" } });
    await assert.rejects(() => listTicketLinks(client, ID_1, ACTOR_ID), TicketQueryError);
  });

  test("listTicketLinkEvents is cursor-paginated (occurred_at, id), never OFFSET", async () => {
    const { client, calls } = fakeClient({
      data: [{
        id: ID_1, entity_type: "shipment", entity_id: ID_2, relationship: "primary_subject", event_type: "linked",
        reason: null, actor_auth_user_id: ACTOR_ID, actor_label: "admin", occurred_at: "2026-08-01T00:00:00Z",
      }],
      error: null,
    });
    const result = await listTicketLinkEvents(client, ID_1, ACTOR_ID, { cursorOccurredAt: "2026-08-01T00:00:00Z", cursorId: ID_2, limit: 25 });
    assert.equal(calls[0]?.fn, "list_ticket_link_events");
    assert.deepEqual(calls[0]?.args, { p_ticket_id: ID_1, p_actor_auth_user_id: ACTOR_ID, p_cursor_occurred_at: "2026-08-01T00:00:00Z", p_cursor_id: ID_2, p_limit: 25 });
    assert.equal(result[0]?.eventType, "linked");
  });
});
