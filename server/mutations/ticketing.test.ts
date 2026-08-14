import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createTicketQueue,
  createTicketCategory,
  addTicketQueueMember,
  removeTicketQueueMember,
  createTicket,
  createTicketForEmployee,
  replyToTicket,
  redactTicketMessage,
  addTicketWatcher,
  removeTicketWatcher,
  assignTicket,
  transferTicketQueue,
  updateTicketClassification,
  transitionTicketStatus,
  setTicketCategoryCustomerVisibility,
  createCustomerTicket,
  replyToCustomerTicket,
  createHelpdeskTicket,
  replyToHelpdeskTicket,
  setTicketCategoryHelpdeskVisibility,
  createSupportQueue,
  assignHelpdeskTicket,
  transferHelpdeskSupportQueue,
  updateHelpdeskTicketClassification,
  linkHelpdeskSupportGrant,
  TicketMutationError,
  type TicketMutationRpcClient,
} from "./ticketing.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: TicketMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TicketMutationRpcClient;
  return { client, calls };
}

describe("catalog/queue-staffing mutations", () => {
  test("createTicketQueue forwards every field to create_ticket_queue", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await createTicketQueue(client, { tenantId: TENANT_ID, orgUnitId: ID_1, code: "IT", name: "IT Support", description: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
    assert.equal(calls[0]?.fn, "create_ticket_queue");
    assert.equal(calls[0]?.args.p_code, "IT");
  });

  test("createTicketCategory forwards defaultQueueId as p_default_queue_id", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await createTicketCategory(client, { tenantId: TENANT_ID, code: "HARDWARE", name: "Hardware", defaultQueueId: ID_1, actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
    assert.equal(calls[0]?.args.p_default_queue_id, ID_1);
  });

  test("addTicketQueueMember/removeTicketQueueMember call the right RPCs", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await addTicketQueueMember(client, { queueId: ID_1, employeeId: ID_2, actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
    await removeTicketQueueMember(client, { memberId: ID_1, expectedVersion: 1, reason: "left team", actorAuthUserId: ACTOR_ID, actorLabel: "admin" });
    assert.equal(calls[0]?.fn, "add_ticket_queue_member");
    assert.equal(calls[1]?.fn, "remove_ticket_queue_member");
  });

  test("insufficient_authority is classified, not swallowed into a generic mutation_failed", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks TKT:Edit for tenant X" } });
    await assert.rejects(
      () => createTicketQueue(client, { tenantId: TENANT_ID, orgUnitId: ID_1, code: "IT", name: "IT Support", description: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin" }),
      (err: unknown) => {
        assert.ok(err instanceof TicketMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("ticket creation mutations", () => {
  test("createTicket forwards a null queueId (category default resolution happens server-side)", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await createTicket(client, { tenantId: TENANT_ID, categoryId: ID_1, queueId: null, priority: "high", subject: "Laptop broken", body: "Black screen.", idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "requester1" });
    assert.equal(calls[0]?.fn, "create_ticket");
    assert.equal(calls[0]?.args.p_queue_id, null);
  });

  test("createTicketForEmployee forwards the explicit requesterEmployeeId (on-behalf, TKT:Edit-gated server-side)", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await createTicketForEmployee(client, { tenantId: TENANT_ID, requesterEmployeeId: ID_2, categoryId: ID_1, queueId: null, priority: "normal", subject: "AC broken", body: "The AC is broken.", idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    assert.equal(calls[0]?.fn, "create_ticket_for_employee");
    assert.equal(calls[0]?.args.p_requester_employee_id, ID_2);
  });

  test("idempotency_key_conflict classified distinctly from mutation_failed", async () => {
    const { client } = fakeClient({ data: null, error: { message: "idempotency_key_conflict: key was already used for a different ticket" } });
    await assert.rejects(
      () => createTicket(client, { tenantId: TENANT_ID, categoryId: ID_1, queueId: null, priority: "normal", subject: "x", body: "y", idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "requester1" }),
      (err: unknown) => {
        assert.ok(err instanceof TicketMutationError);
        assert.equal(err.code, "idempotency_key_conflict");
        return true;
      },
    );
  });
});

describe("conversation mutations", () => {
  test("replyToTicket forwards visibility and attachmentFileIds unchanged", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await replyToTicket(client, { ticketId: ID_1, body: "Internal note.", visibility: "internal", attachmentFileIds: [ID_2], idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    assert.equal(calls[0]?.args.p_visibility, "internal");
    assert.deepEqual(calls[0]?.args.p_attachment_file_ids, [ID_2]);
  });

  test("redactTicketMessage requires a non-empty reason (Zod-enforced client-side, mirrors the RPC's own reason_required)", async () => {
    const { client } = fakeClient({ data: {}, error: null });
    await assert.rejects(() => redactTicketMessage(client, { messageId: ID_1, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "staff1" }));
  });
});

describe("watcher mutations", () => {
  test("addTicketWatcher/removeTicketWatcher call the right RPCs", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await addTicketWatcher(client, { ticketId: ID_1, employeeId: ID_2, actorAuthUserId: ACTOR_ID, actorLabel: "requester1" });
    await removeTicketWatcher(client, { watcherId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "requester1" });
    assert.equal(calls[0]?.fn, "add_ticket_watcher");
    assert.equal(calls[1]?.fn, "remove_ticket_watcher");
  });
});

describe("lifecycle mutations", () => {
  test("assignTicket forwards a null assigneeEmployeeId (unassign)", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await assignTicket(client, { ticketId: ID_1, expectedVersion: 2, assigneeEmployeeId: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    assert.equal(calls[0]?.args.p_assignee_employee_id, null);
  });

  test("transferTicketQueue requires a non-empty reason", async () => {
    const { client } = fakeClient({ data: {}, error: null });
    await assert.rejects(() => transferTicketQueue(client, { ticketId: ID_1, expectedVersion: 1, newQueueId: ID_2, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "staff1" }));
  });

  test("updateTicketClassification forwards category and priority", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await updateTicketClassification(client, { ticketId: ID_1, expectedVersion: 1, categoryId: ID_2, priority: "urgent", actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    assert.equal(calls[0]?.args.p_category_id, ID_2);
    assert.equal(calls[0]?.args.p_priority, "urgent");
  });

  test("transitionTicketStatus allows a null reason client-side (server enforces per-transition requires_reason)", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await transitionTicketStatus(client, { ticketId: ID_1, expectedVersion: 1, toStatus: "open", reason: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    assert.equal(calls[0]?.args.p_reason, null);
  });

  test("stale_version classified distinctly (optimistic concurrency loser)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "stale_version: expected version 1 but current version is 2" } });
    await assert.rejects(
      () => transitionTicketStatus(client, { ticketId: ID_1, expectedVersion: 1, toStatus: "open", reason: null, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" }),
      (err: unknown) => {
        assert.ok(err instanceof TicketMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("HRT-287 (CG-S12-HRT-015): customer-channel and category-visibility mutations", () => {
  test("setTicketCategoryCustomerVisibility forwards the boolean flag", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await setTicketCategoryCustomerVisibility(client, { categoryId: ID_1, customerVisible: true, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    assert.equal(calls[0]?.fn, "set_ticket_category_customer_visibility");
    assert.equal(calls[0]?.args.p_customer_visible, true);
  });

  test("createCustomerTicket forwards accountId as p_account_id -- no p_queue_id parameter exists to forge", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await createCustomerTicket(client, { tenantId: TENANT_ID, accountId: ID_1, categoryId: ID_2, priority: "normal", subject: "Invoice discrepancy", body: "My invoice total is wrong.", idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "Customer A1" });
    assert.equal(calls[0]?.fn, "create_customer_ticket");
    assert.equal(calls[0]?.args.p_account_id, ID_1);
    assert.equal((calls[0]?.args as Record<string, unknown>).p_queue_id, undefined);
  });

  test("account_not_available is classified distinctly (forged/unowned account id)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "account_not_available: X is not an account this identity may file a ticket for" } });
    await assert.rejects(
      () => createCustomerTicket(client, { tenantId: TENANT_ID, accountId: ID_1, categoryId: ID_2, priority: "normal", subject: "x", body: "y", idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "Customer A1" }),
      (err: unknown) => {
        assert.ok(err instanceof TicketMutationError);
        assert.equal(err.code, "account_not_available");
        return true;
      },
    );
  });

  test("replyToCustomerTicket calls reply_to_customer_ticket, not the internal reply_to_ticket -- no visibility parameter to forward", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await replyToCustomerTicket(client, { ticketId: ID_1, body: "Any update?", attachmentFileIds: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "Customer A1" });
    assert.equal(calls[0]?.fn, "reply_to_customer_ticket");
    assert.equal((calls[0]?.args as Record<string, unknown>).p_visibility, undefined);
  });
});

describe("HRT-288 (CG-S12-HRT-016): tenant-side helpdesk mutations", () => {
  test("createHelpdeskTicket forwards severity/environment/reference -- no p_account_id/p_queue_id parameter exists to forge", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await createHelpdeskTicket(client, {
      tenantId: TENANT_ID, categoryId: ID_1, priority: "normal", severity: "high", productArea: "Billing",
      environment: "production", externalReference: "PO-4471", subject: "Invoice mismatch", body: "Our invoice is wrong.",
      idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "Tenant Admin",
    });
    assert.equal(calls[0]?.fn, "create_helpdesk_ticket");
    assert.equal(calls[0]?.args.p_severity, "high");
    assert.equal((calls[0]?.args as Record<string, unknown>).p_account_id, undefined);
    assert.equal((calls[0]?.args as Record<string, unknown>).p_queue_id, undefined);
  });

  test("insufficient_authority is classified for an unauthorized tenant actor (not tenant_admin/TKT:Edit)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: identity X is not authorized to open a CargoGrid support case for tenant Y" } });
    await assert.rejects(
      () =>
        createHelpdeskTicket(client, {
          tenantId: TENANT_ID, categoryId: ID_1, priority: "normal", severity: null, productArea: null, environment: null,
          externalReference: null, subject: "x", body: "y", idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "Bystander",
        }),
      (err: unknown) => {
        assert.ok(err instanceof TicketMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("replyToHelpdeskTicket calls reply_to_helpdesk_ticket -- no visibility parameter to forward", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await replyToHelpdeskTicket(client, { ticketId: ID_1, body: "Any update?", attachmentFileIds: null, idempotencyKey: null, actorAuthUserId: ACTOR_ID, actorLabel: "Tenant Admin" });
    assert.equal(calls[0]?.fn, "reply_to_helpdesk_ticket");
    assert.equal((calls[0]?.args as Record<string, unknown>).p_visibility, undefined);
  });

  test("setTicketCategoryHelpdeskVisibility forwards the boolean flag", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await setTicketCategoryHelpdeskVisibility(client, { categoryId: ID_1, helpdeskVisible: true, actorAuthUserId: ACTOR_ID, actorLabel: "staff1" });
    assert.equal(calls[0]?.fn, "set_ticket_category_helpdesk_visibility");
    assert.equal(calls[0]?.args.p_helpdesk_visible, true);
  });
});

describe("HRT-288: Platform-side (Supreme-Admin-gated) helpdesk mutations", () => {
  test("createSupportQueue calls create_support_queue", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await createSupportQueue(client, { code: "SQ-BILLING", name: "Billing Support", description: null, actorAuthUserId: ACTOR_ID, actorLabel: "supreme" });
    assert.equal(calls[0]?.fn, "create_support_queue");
    assert.equal(calls[0]?.args.p_code, "SQ-BILLING");
  });

  test("assignHelpdeskTicket forwards a nullable assigneeAuthUserId (unassign)", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await assignHelpdeskTicket(client, { ticketId: ID_1, expectedVersion: 2, assigneeAuthUserId: null, actorAuthUserId: ACTOR_ID, actorLabel: "supreme" });
    assert.equal(calls[0]?.fn, "assign_helpdesk_ticket");
    assert.equal(calls[0]?.args.p_assignee_auth_user_id, null);
  });

  test("assignee_not_support_staff is classified distinctly", async () => {
    const { client } = fakeClient({ data: null, error: { message: "assignee_not_support_staff: X does not hold Platform support (Supreme Admin) authority" } });
    await assert.rejects(
      () => assignHelpdeskTicket(client, { ticketId: ID_1, expectedVersion: 1, assigneeAuthUserId: ID_2, actorAuthUserId: ACTOR_ID, actorLabel: "supreme" }),
      (err: unknown) => {
        assert.ok(err instanceof TicketMutationError);
        assert.equal(err.code, "assignee_not_support_staff");
        return true;
      },
    );
  });

  test("transferHelpdeskSupportQueue forwards the target support queue and reason", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await transferHelpdeskSupportQueue(client, { ticketId: ID_1, expectedVersion: 1, newSupportQueueId: ID_2, reason: "route to billing", actorAuthUserId: ACTOR_ID, actorLabel: "supreme" });
    assert.equal(calls[0]?.fn, "transfer_helpdesk_support_queue");
    assert.equal(calls[0]?.args.p_new_support_queue_id, ID_2);
  });

  test("updateHelpdeskTicketClassification forwards severity/product area/environment alongside category/priority", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await updateHelpdeskTicketClassification(client, { ticketId: ID_1, expectedVersion: 1, categoryId: ID_2, priority: "urgent", severity: "critical", productArea: "Rate cards", environment: "production", actorAuthUserId: ACTOR_ID, actorLabel: "supreme" });
    assert.equal(calls[0]?.args.p_severity, "critical");
    assert.equal(calls[0]?.args.p_priority, "urgent");
  });

  test("linkHelpdeskSupportGrant forwards a nullable caseRef (unlink) and classifies support_grant_not_found distinctly", async () => {
    const { client, calls } = fakeClient({ data: {}, error: null });
    await linkHelpdeskSupportGrant(client, { ticketId: ID_1, expectedVersion: 1, caseRef: null, actorAuthUserId: ACTOR_ID, actorLabel: "supreme" });
    assert.equal(calls[0]?.fn, "link_helpdesk_support_grant");
    assert.equal(calls[0]?.args.p_case_ref, null);

    const { client: client2 } = fakeClient({ data: null, error: { message: "support_grant_not_found: no support access grant exists for case CASE-X in tenant Y" } });
    await assert.rejects(
      () => linkHelpdeskSupportGrant(client2, { ticketId: ID_1, expectedVersion: 1, caseRef: "CASE-X", actorAuthUserId: ACTOR_ID, actorLabel: "supreme" }),
      (err: unknown) => {
        assert.ok(err instanceof TicketMutationError);
        assert.equal(err.code, "support_grant_not_found");
        return true;
      },
    );
  });
});
