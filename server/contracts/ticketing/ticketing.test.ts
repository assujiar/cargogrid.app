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
