import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseTicketQueueRow,
  parseTicketCategoryRow,
  parseTicketQueueMemberRow,
  parseTicketDetail,
  parseTicketListRow,
  parseMyTicketListRow,
  parseTicketMessageRow,
  parseTicketWatcherRow,
  parseTicketEventRow,
  parseTicketExportRow,
  parseCustomerAccountRow,
  parseCustomerTicketCategoryRow,
  parseCustomerTicketDetail,
  parseCustomerTicketListRow,
  parseCustomerTicketMessageRow,
  CreateTicketInputSchema,
  CreateTicketForEmployeeInputSchema,
  ReplyToTicketInputSchema,
  TransitionTicketStatusInputSchema,
  CreateCustomerTicketInputSchema,
  ReplyToCustomerTicketInputSchema,
  parseHelpdeskTicketCategoryRow,
  parseHelpdeskTicketDetail,
  parseHelpdeskTicketListRow,
  parseHelpdeskTicketMessageRow,
  parseSupportQueueRow,
  parsePlatformHelpdeskTicketListRow,
  parsePlatformHelpdeskTicketDetail,
  CreateHelpdeskTicketInputSchema,
  ReplyToHelpdeskTicketInputSchema,
  LinkHelpdeskSupportGrantInputSchema,
  TICKET_CHANNELS,
  parseSlaPolicyVersionRow,
  parseTicketSlaClockRow,
  parseTicketSlaStatusForRequesterRow,
  parseTicketSlaClockEventRow,
  CreateSlaPolicyVersionInputSchema,
  PauseTicketSlaClockInputSchema,
  parseTicketRoutingRuleVersionRow,
  parseTicketRoutingPreviewRow,
  parseTicketAssignmentCandidateRow,
  parseTicketAssignmentEventRow,
  AssignTicketInputSchema,
  CreateTicketRoutingRuleVersionInputSchema,
  DeclineTicketAssignmentInputSchema,
  TICKET_ASSIGNMENT_EVENT_TYPES,
} from "./ticketing.ts";

const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACTOR = "423e4567-e89b-12d3-a456-426614174000";

describe("parseTicketQueueRow / parseTicketCategoryRow / parseTicketQueueMemberRow", () => {
  test("maps a queue row", () => {
    const q = parseTicketQueueRow({ id: ID_1, org_unit_id: ID_2, code: "IT", name: "IT Support", description: null, status: "active", record_version: 1 });
    assert.equal(q.code, "IT");
    assert.equal(q.description, null);
  });

  test("maps a category row with a null default_queue_id", () => {
    const c = parseTicketCategoryRow({ id: ID_1, code: "HARDWARE", name: "Hardware", default_queue_id: null, status: "active", record_version: 1 });
    assert.equal(c.defaultQueueId, null);
  });

  test("maps a queue member row", () => {
    const m = parseTicketQueueMemberRow({ id: ID_1, queue_id: ID_2, employee_id: ID_1, employee_name: "Staff One", status: "active", added_by: "admin", added_at: "2026-01-01T00:00:00Z", record_version: 1 });
    assert.equal(m.employeeName, "Staff One");
  });
});

describe("parseTicketListRow / parseMyTicketListRow / parseTicketDetail", () => {
  test("maps a list row, nulls carried through for an unassigned ticket", () => {
    const t = parseTicketListRow({
      id: ID_1, ticket_number: "TKT-2026-000001", subject: "Laptop broken", status: "new", priority: "high",
      category_code: "HARDWARE", queue_code: "IT", requester_employee_id: ID_2, requester_name: "Requester One",
      assignee_employee_id: null, assignee_name: null, record_version: 1, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z",
    });
    assert.equal(t.status, "new");
    assert.equal(t.assigneeEmployeeId, null);
  });

  test("maps a my-tickets row", () => {
    const t = parseMyTicketListRow({
      id: ID_1, ticket_number: "TKT-2026-000001", subject: "Laptop broken", status: "open", priority: "normal",
      category_code: "HARDWARE", queue_code: "IT", assignee_employee_id: ID_2, assignee_name: "Staff One",
      record_version: 2, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-02T00:00:00Z",
    });
    assert.equal(t.assigneeName, "Staff One");
  });

  test("maps a full ticket detail, staff/requester viewer flags carried through", () => {
    const d = parseTicketDetail({
      id: ID_1, tenant_id: TENANT_ID, ticket_number: "TKT-2026-000001", channel: "internal",
      category_id: ID_2, category_code: "HARDWARE", category_name: "Hardware Issue",
      queue_id: ID_2, queue_code: "IT", queue_name: "IT Support",
      priority: "high", subject: "Laptop broken", status: "resolved",
      requester_employee_id: ID_2, requester_name: "Requester One", requested_by_auth_user_id: ID_2, requested_by: "requester1",
      assignee_employee_id: ID_1, assignee_name: "Staff One", assigned_at: "2026-01-01T00:00:00Z",
      resolution_summary: "Replaced the battery.", resolved_at: "2026-01-02T00:00:00Z", closed_at: null,
      cancelled_reason: null, cancelled_at: null, reopen_count: 0,
      record_version: 3, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-02T00:00:00Z",
      is_staff_viewer: true, is_requester_viewer: false,
    });
    assert.equal(d.isStaffViewer, true);
    assert.equal(d.isRequesterViewer, false);
    assert.equal(d.resolutionSummary, "Replaced the battery.");
  });
});

describe("parseTicketMessageRow / parseTicketWatcherRow / parseTicketEventRow / parseTicketExportRow", () => {
  test("maps a public message row with attachments", () => {
    const m = parseTicketMessageRow({
      id: ID_1, ticket_id: ID_2, visibility: "public", body: "Have you tried rebooting?", is_redacted: false,
      attachment_file_ids: [ID_1, ID_2], author_auth_user_id: ACTOR, author_label: "staff1", author_role: "staff",
      created_at: "2026-01-01T00:00:00Z", record_version: 1,
    });
    assert.equal(m.visibility, "public");
    assert.deepEqual(m.attachmentFileIds, [ID_1, ID_2]);
  });

  test("maps a redacted message row -- body is already server-overwritten, never the original", () => {
    const m = parseTicketMessageRow({
      id: ID_1, ticket_id: ID_2, visibility: "internal", body: "[redacted]", is_redacted: true,
      attachment_file_ids: [], author_auth_user_id: ACTOR, author_label: "staff1", author_role: "staff",
      created_at: "2026-01-01T00:00:00Z", record_version: 2,
    });
    assert.equal(m.isRedacted, true);
    assert.equal(m.body, "[redacted]");
  });

  test("maps a watcher row", () => {
    const w = parseTicketWatcherRow({ id: ID_1, ticket_id: ID_2, employee_id: ID_1, employee_name: "Bystander", status: "active", added_by: "requester1", added_at: "2026-01-01T00:00:00Z", record_version: 1 });
    assert.equal(w.status, "active");
  });

  test("maps a status_change event row", () => {
    const e = parseTicketEventRow({ id: ID_1, ticket_id: ID_2, event_type: "status_change", from_value: "new", to_value: "open", reason: null, actor_auth_user_id: ACTOR, actor_label: "staff1", occurred_at: "2026-01-01T00:00:00Z" });
    assert.equal(e.eventType, "status_change");
    assert.equal(e.fromValue, "new");
  });

  test("maps an export row -- no message body or free-text reason field exists on this shape", () => {
    const r = parseTicketExportRow({
      ticket_number: "TKT-2026-000001", subject: "Laptop broken", status: "closed", priority: "high",
      category_code: "HARDWARE", queue_code: "IT", requester_name: "Requester One", assignee_name: "Staff One",
      created_at: "2026-01-01T00:00:00Z", resolved_at: "2026-01-02T00:00:00Z", closed_at: "2026-01-03T00:00:00Z",
    });
    assert.equal(r.status, "closed");
    assert.equal((r as unknown as Record<string, unknown>).resolutionSummary, undefined);
  });
});

describe("mutation input schemas", () => {
  test("CreateTicketInputSchema requires a non-empty subject and body", () => {
    assert.throws(() =>
      CreateTicketInputSchema.parse({ tenantId: TENANT_ID, categoryId: ID_1, queueId: null, priority: "normal", subject: "", body: "x", idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "requester1" }),
    );
  });

  test("CreateTicketForEmployeeInputSchema extends CreateTicketInputSchema with a required requesterEmployeeId", () => {
    const v = CreateTicketForEmployeeInputSchema.parse({
      tenantId: TENANT_ID, categoryId: ID_1, queueId: ID_2, priority: "normal", subject: "AC broken", body: "The AC is broken.",
      idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "staff1", requesterEmployeeId: ID_2,
    });
    assert.equal(v.requesterEmployeeId, ID_2);
  });

  test("ReplyToTicketInputSchema rejects an invalid visibility value", () => {
    assert.throws(() =>
      ReplyToTicketInputSchema.parse({ ticketId: ID_1, body: "hi", visibility: "secret", attachmentFileIds: null, idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "staff1" }),
    );
  });

  test("TransitionTicketStatusInputSchema accepts a null reason (only enforced server-side per-transition)", () => {
    const v = TransitionTicketStatusInputSchema.parse({ ticketId: ID_1, expectedVersion: 1, toStatus: "open", reason: null, actorAuthUserId: ACTOR, actorLabel: "staff1" });
    assert.equal(v.reason, null);
  });
});

describe("HRT-287 (CG-S12-HRT-015): customer-facing row parsers and mutation inputs", () => {
  test("parseCustomerAccountRow maps a scoped account", () => {
    const a = parseCustomerAccountRow({ account_id: ID_1, legal_name: "Acme Logistics", parent_account_id: null });
    assert.equal(a.legalName, "Acme Logistics");
    assert.equal(a.parentAccountId, null);
  });

  test("parseCustomerTicketCategoryRow carries no default_queue_id/status -- a deliberately narrower shape than the staff TicketCategoryRow", () => {
    const c = parseCustomerTicketCategoryRow({ id: ID_1, code: "BILLING", name: "Billing Question" });
    assert.equal(c.name, "Billing Question");
    assert.equal((c as unknown as Record<string, unknown>).defaultQueueId, undefined);
  });

  test("parseCustomerTicketListRow carries account identity, never queue/assignee identity", () => {
    const t = parseCustomerTicketListRow({
      id: ID_1, ticket_number: "TKT-2026-000001", subject: "Invoice discrepancy", status: "new", priority: "normal",
      category_name: "Billing Question", account_id: ID_2, account_name: "Acme Logistics",
      record_version: 1, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z",
    });
    assert.equal(t.accountName, "Acme Logistics");
    assert.equal((t as unknown as Record<string, unknown>).queueCode, undefined);
    assert.equal((t as unknown as Record<string, unknown>).assigneeEmployeeId, undefined);
  });

  test("parseCustomerTicketDetail includes resolution_summary/cancelled_reason (communicated back to the requester) but no queue/assignee field", () => {
    const d = parseCustomerTicketDetail({
      id: ID_1, ticket_number: "TKT-2026-000001", subject: "Invoice discrepancy", status: "resolved", priority: "normal",
      category_name: "Billing Question", account_id: ID_2, account_name: "Acme Logistics",
      resolution_summary: "Corrected the invoice.", cancelled_reason: null, last_reopen_reason: null, reopen_count: 0,
      record_version: 2, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-02T00:00:00Z", resolved_at: "2026-01-02T00:00:00Z", closed_at: null,
    });
    assert.equal(d.resolutionSummary, "Corrected the invoice.");
    assert.equal((d as unknown as Record<string, unknown>).assigneeEmployeeId, undefined);
    assert.equal((d as unknown as Record<string, unknown>).queueId, undefined);
  });

  test("parseCustomerTicketMessageRow uses author_display (genericized for staff), never a raw staff author_label", () => {
    const m = parseCustomerTicketMessageRow({
      id: ID_1, ticket_id: ID_2, body: "Looking into this now.", is_redacted: false, attachment_file_ids: [],
      author_role: "staff", author_display: "Support Team", created_at: "2026-01-01T00:00:00Z", record_version: 1,
    });
    assert.equal(m.authorDisplay, "Support Team");
    assert.equal((m as unknown as Record<string, unknown>).authorLabel, undefined);
  });

  test("CreateCustomerTicketInputSchema requires accountId (validated server-side against membership scope, never trusted alone)", () => {
    const v = CreateCustomerTicketInputSchema.parse({
      tenantId: TENANT_ID, accountId: ID_1, categoryId: ID_2, priority: "normal", subject: "Invoice discrepancy",
      body: "My invoice total does not match the quote.", idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "Customer A1",
    });
    assert.equal(v.accountId, ID_1);
    assert.throws(() => CreateCustomerTicketInputSchema.parse({ tenantId: TENANT_ID, categoryId: ID_2, priority: "normal", subject: "x", body: "x", idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "x" }));
  });

  test("ReplyToCustomerTicketInputSchema has no visibility field at all -- always public, structurally", () => {
    const v = ReplyToCustomerTicketInputSchema.parse({ ticketId: ID_1, body: "Any update?", attachmentFileIds: null, idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "Customer A1" });
    assert.equal((v as unknown as Record<string, unknown>).visibility, undefined);
  });
});

describe("HRT-288 helpdesk channel/rows/inputs", () => {
  test("TICKET_CHANNELS includes helpdesk alongside internal/customer", () => {
    assert.deepEqual(TICKET_CHANNELS, ["internal", "customer", "helpdesk"]);
  });

  test("parseHelpdeskTicketCategoryRow maps a bare category row", () => {
    const c = parseHelpdeskTicketCategoryRow({ id: ID_1, code: "CAT-SUPPORT", name: "Platform Support" });
    assert.equal(c.code, "CAT-SUPPORT");
  });

  test("parseHelpdeskTicketListRow carries severity but no queue/assignee identity", () => {
    const t = parseHelpdeskTicketListRow({
      id: ID_1, ticket_number: "TKT-2026-000001", subject: "Invoice mismatch", status: "new", priority: "high", severity: "high",
      category_name: "Platform Support", record_version: 1, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z",
    });
    assert.equal(t.severity, "high");
    assert.equal((t as unknown as Record<string, unknown>).supportQueueId, undefined);
    assert.equal((t as unknown as Record<string, unknown>).assigneeSupportAuthUserId, undefined);
  });

  test("parseHelpdeskTicketDetail: resolutionSummary is nullable (always null from the RPC, staff-authored by construction) and no support_queue/assignee/case_ref field exists", () => {
    const d = parseHelpdeskTicketDetail({
      id: ID_1, ticket_number: "TKT-2026-000001", subject: "Invoice mismatch", status: "open", priority: "high",
      severity: "high", product_area: "Billing", environment: "production", external_reference: "PO-4471",
      category_name: "Platform Support", resolution_summary: null, cancelled_reason: null, last_reopen_reason: null,
      reopen_count: 0, record_version: 1, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z", resolved_at: null, closed_at: null,
    });
    assert.equal(d.resolutionSummary, null);
    assert.equal((d as unknown as Record<string, unknown>).supportQueueId, undefined);
    assert.equal((d as unknown as Record<string, unknown>).supportAccessCaseRef, undefined);
    assert.equal((d as unknown as Record<string, unknown>).assigneeSupportAuthUserId, undefined);
  });

  test("parseHelpdeskTicketMessageRow genericizes a staff author, mirroring the customer channel's own discipline", () => {
    const m = parseHelpdeskTicketMessageRow({
      id: ID_1, ticket_id: ID_2, body: "Looking into this now.", is_redacted: false, attachment_file_ids: [],
      author_role: "staff", author_display: "CargoGrid Support", created_at: "2026-01-01T00:00:00Z", record_version: 1,
    });
    assert.equal(m.authorDisplay, "CargoGrid Support");
    assert.equal((m as unknown as Record<string, unknown>).authorLabel, undefined);
  });

  test("parseSupportQueueRow maps a Platform-global queue row", () => {
    const q = parseSupportQueueRow({ id: ID_1, code: "SQ-BILLING", name: "Billing Support", description: null, status: "active", record_version: 1 });
    assert.equal(q.code, "SQ-BILLING");
  });

  test("parsePlatformHelpdeskTicketListRow carries tenant identity and support-queue/assignee identity (the Platform-only richer shape)", () => {
    const t = parsePlatformHelpdeskTicketListRow({
      id: ID_1, ticket_number: "TKT-2026-000001", tenant_id: TENANT_ID, tenant_name: "Acme Logistics",
      subject: "Invoice mismatch", status: "new", priority: "high", severity: "high", product_area: "Billing",
      support_queue_id: ID_2, support_queue_code: "SQ-BILLING", assignee_support_auth_user_id: null, assignee_email: null,
      support_access_case_ref: null, record_version: 1, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z",
    });
    assert.equal(t.tenantName, "Acme Logistics");
    assert.equal(t.supportQueueCode, "SQ-BILLING");
  });

  test("parsePlatformHelpdeskTicketDetail carries the support-grant correlation display fields", () => {
    const d = parsePlatformHelpdeskTicketDetail({
      id: ID_1, ticket_number: "TKT-2026-000001", tenant_id: TENANT_ID, tenant_name: "Acme Logistics", subject: "Invoice mismatch",
      status: "open", priority: "high", severity: "high", product_area: "Billing", environment: "production", external_reference: "PO-4471",
      category_name: "Platform Support", support_queue_id: ID_2, support_queue_code: "SQ-BILLING",
      assignee_support_auth_user_id: null, assignee_email: null, support_access_case_ref: "CASE-500",
      support_grant_status: "revoked", support_grant_expires_at: "2026-01-02T00:00:00Z", support_grant_revoked_at: "2026-01-01T12:00:00Z",
      resolution_summary: null, cancelled_reason: null, last_reopen_reason: null, reopen_count: 0,
      record_version: 1, created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z", resolved_at: null, closed_at: null,
    });
    assert.equal(d.supportAccessCaseRef, "CASE-500");
    assert.equal(d.supportGrantStatus, "revoked");
  });

  test("CreateHelpdeskTicketInputSchema has no accountId/queueId-shaped field to spoof", () => {
    const v = CreateHelpdeskTicketInputSchema.parse({
      tenantId: TENANT_ID, categoryId: ID_1, priority: "normal", severity: "high", productArea: "Billing",
      environment: "production", externalReference: "PO-4471", subject: "Invoice mismatch", body: "Our invoice does not match the rate card.",
      idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "Tenant Admin",
    });
    assert.equal(v.severity, "high");
    assert.equal((v as unknown as Record<string, unknown>).queueId, undefined);
    assert.equal((v as unknown as Record<string, unknown>).accountId, undefined);
  });

  test("ReplyToHelpdeskTicketInputSchema has no visibility field at all -- always public, structurally", () => {
    const v = ReplyToHelpdeskTicketInputSchema.parse({ ticketId: ID_1, body: "Any update?", attachmentFileIds: null, idempotencyKey: null, actorAuthUserId: ACTOR, actorLabel: "Tenant Admin" });
    assert.equal((v as unknown as Record<string, unknown>).visibility, undefined);
  });

  test("LinkHelpdeskSupportGrantInputSchema allows a null caseRef (unlink)", () => {
    const v = LinkHelpdeskSupportGrantInputSchema.parse({ ticketId: ID_1, expectedVersion: 1, caseRef: null, actorAuthUserId: ACTOR, actorLabel: "Supreme" });
    assert.equal(v.caseRef, null);
  });
});

describe("HRT-289 SLA contract", () => {
  test("parseSlaPolicyVersionRow carries scope/target/precedence through, nulls preserved for wildcard dimensions", () => {
    const v = parseSlaPolicyVersionRow({
      id: ID_1, version_number: 2, status: "published", channel: "internal", category_id: null, priority: null,
      customer_account_id: null, queue_id: null, support_queue_id: null, calendar_id: ID_2,
      response_target_minutes: 60, resolution_target_minutes: 480, precedence_rank: 0,
      published_at: "2026-01-01T00:00:00Z", record_version: 1,
    });
    assert.equal(v.channel, "internal");
    assert.equal(v.categoryId, null);
    assert.equal(v.responseTargetMinutes, 60);
  });

  test("parseTicketSlaClockRow maps the full staff-facing projection, including calendar/policy identity", () => {
    const c = parseTicketSlaClockRow({
      id: ID_1, ticket_id: ID_2, sla_policy_version_id: ID_1, sla_calendar_version_id: ID_2, status: "running",
      started_at: "2026-01-01T00:00:00Z", response_target_minutes: 60, response_status: "pending", response_met_at: null,
      response_breached_at: null, resolution_target_minutes: 480, resolution_status: "pending", resolution_met_at: null,
      resolution_breached_at: null, last_evaluated_at: null, record_version: 1,
    });
    assert.equal(c.slaPolicyVersionId, ID_1);
    assert.equal(c.status, "running");
  });

  test("parseTicketSlaStatusForRequesterRow carries ONLY target/status -- structurally cannot carry a calendar/policy id (not in the schema at all)", () => {
    const r = parseTicketSlaStatusForRequesterRow({
      ticket_id: ID_1, response_target_minutes: 60, response_status: "met", resolution_target_minutes: 480, resolution_status: "pending",
    });
    assert.equal(r.responseStatus, "met");
    assert.equal((r as unknown as Record<string, unknown>).slaPolicyVersionId, undefined);
    assert.equal((r as unknown as Record<string, unknown>).slaCalendarVersionId, undefined);
  });

  test("parseTicketSlaClockEventRow maps a reminder event with its threshold", () => {
    const e = parseTicketSlaClockEventRow({
      id: ID_1, phase: "response", event_type: "reminder", reminder_threshold_pct: 80, business_minutes_elapsed: 48,
      occurred_at: "2026-01-01T00:00:00Z", actor_label: null, reason: null,
    });
    assert.equal(e.eventType, "reminder");
    assert.equal(e.reminderThresholdPct, 80);
  });

  test("CreateSlaPolicyVersionInputSchema accepts a fully-wildcard scope (channel-only default policy)", () => {
    const v = CreateSlaPolicyVersionInputSchema.parse({
      policyId: ID_1, channel: "customer", categoryId: null, priority: null, customerAccountId: null, queueId: null,
      supportQueueId: null, calendarId: ID_2, responseTargetMinutes: 30, resolutionTargetMinutes: 240, precedenceRank: 0,
      actorAuthUserId: ACTOR, actorLabel: "Admin",
    });
    assert.equal(v.channel, "customer");
    assert.equal(v.categoryId, null);
  });

  test("PauseTicketSlaClockInputSchema rejects a pause reason code outside the closed set", () => {
    assert.throws(() =>
      PauseTicketSlaClockInputSchema.parse({ ticketId: ID_1, expectedVersion: 1, pauseReasonCode: "made_up", reason: null, actorAuthUserId: ACTOR, actorLabel: "Staff" })
    );
  });
});

describe("HRT-290 (CG-S12-HRT-018) ticket assignment contracts", () => {
  test("parseTicketRoutingRuleVersionRow maps the scope/target/mode tuple", () => {
    const v = parseTicketRoutingRuleVersionRow({
      id: ID_1, version_number: 1, status: "published", channel: "internal", category_id: ID_2, priority: "urgent",
      target_queue_id: ID_1, assignment_mode: "least_loaded", max_active_assignments_per_member: 2,
      precedence_rank: 5, published_at: "2026-08-01T00:00:00Z", record_version: 1,
    });
    assert.equal(v.assignmentMode, "least_loaded");
    assert.equal(v.maxActiveAssignmentsPerMember, 2);
    assert.equal(v.priority, "urgent");
  });

  test("parseTicketRoutingPreviewRow handles matched=false with every other field null", () => {
    const r = parseTicketRoutingPreviewRow({
      matched: false, rule_id: null, rule_version_id: null, version_number: null,
      target_queue_id: null, target_queue_code: null, assignment_mode: null, max_active_assignments_per_member: null,
    });
    assert.equal(r.matched, false);
    assert.equal(r.targetQueueId, null);
  });

  test("parseTicketAssignmentCandidateRow never carries a raw permission/role shape -- only eligibility/workload fields", () => {
    const c = parseTicketAssignmentCandidateRow({ employee_id: ID_1, employee_name: "Staff One", is_eligible: false, active_ticket_count: 0, ineligible_reason: "not currently active/available" });
    assert.equal(c.isEligible, false);
    assert.equal(c.ineligibleReason, "not currently active/available");
    assert.equal((c as unknown as Record<string, unknown>).permissions, undefined);
  });

  test("parseTicketAssignmentEventRow maps a reassign event with both from/to identities", () => {
    const e = parseTicketAssignmentEventRow({
      id: ID_1, event_type: "reassign", source: "manual", rule_version_id: null,
      from_assignee_employee_id: ID_1, from_assignee_name: "Staff One", to_assignee_employee_id: ID_2, to_assignee_name: "Staff Two",
      from_queue_id: null, to_queue_id: null, reason: "workload balancing", actor_label: "admin", occurred_at: "2026-08-01T00:00:00Z",
    });
    assert.equal(e.eventType, "reassign");
    assert.equal(e.fromAssigneeName, "Staff One");
    assert.equal(e.toAssigneeName, "Staff Two");
  });

  test("TICKET_ASSIGNMENT_EVENT_TYPES covers claim/accept/decline/reassign/unassign/transfer/auto_route/manual_assign", () => {
    for (const t of ["auto_route", "manual_assign", "claim", "accept", "decline", "reassign", "unassign", "transfer"]) {
      assert.ok((TICKET_ASSIGNMENT_EVENT_TYPES as readonly string[]).includes(t));
    }
  });

  test("AssignTicketInputSchema accepts the widened, optional reason/override fields and defaults them absent", () => {
    const bare = AssignTicketInputSchema.parse({ ticketId: ID_1, expectedVersion: 1, assigneeEmployeeId: ID_2, actorAuthUserId: ACTOR, actorLabel: "staff1" });
    assert.equal(bare.reason, undefined);
    assert.equal(bare.overrideWorkloadLimit, undefined);

    const withOverride = AssignTicketInputSchema.parse({
      ticketId: ID_1, expectedVersion: 1, assigneeEmployeeId: ID_2, actorAuthUserId: ACTOR, actorLabel: "staff1",
      reason: "urgent", overrideWorkloadLimit: true,
    });
    assert.equal(withOverride.overrideWorkloadLimit, true);
  });

  test("CreateTicketRoutingRuleVersionInputSchema rejects channel=helpdesk at the type level (only internal/customer are valid TicketChannel-adjacent scope here in practice, enforced server-side; schema itself accepts any TicketChannel but the RPC rejects helpdesk)", () => {
    // The Zod schema reuses TicketChannelSchema (all three channels) since
    // the CHECK-level restriction to internal/customer lives in the
    // database (decision 2) -- this test documents that the client-side
    // schema is deliberately permissive here, matching every other
    // channel-scoped input in this contract file, and that server-side
    // rejection is what actually enforces the boundary (verified live in
    // scripts/db-tests/ticketing-assignment.sql).
    const v = CreateTicketRoutingRuleVersionInputSchema.parse({
      ruleId: ID_1, channel: "helpdesk", categoryId: null, priority: null, targetQueueId: ID_1,
      assignmentMode: "manual", maxActiveAssignmentsPerMember: null, precedenceRank: 0,
      actorAuthUserId: ACTOR, actorLabel: "staff1",
    });
    assert.equal(v.channel, "helpdesk");
  });

  test("DeclineTicketAssignmentInputSchema requires a non-empty reason", () => {
    assert.throws(() =>
      DeclineTicketAssignmentInputSchema.parse({ ticketId: ID_1, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR, actorLabel: "staff1" })
    );
  });
});
