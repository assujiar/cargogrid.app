import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  AuditTrailMutationError,
  captureAuditEvent,
  supremeAdminDeleteAuditLog,
  supremeAdminMutateAuditLog,
  type AuditTrailMutationRpcClient,
} from "./audit-trail.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const TARGET_ID = "423e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: "523e4567-e89b-12d3-a456-426614174000",
  correlation_id: "623e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  actor_auth_user_id: ACTOR_ID,
  actor_label: "tester",
  action: "create",
  resource_type: "app.org_units",
  resource_id: null,
  result: "success",
  reason: null,
  before_value: null,
  after_value: null,
  occurred_at: "2026-07-16T00:00:00.000Z",
  legal_hold: false,
  legal_hold_reason: null,
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): AuditTrailMutationRpcClient & {
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("captureAuditEvent", () => {
  test("calls capture_audit_event with the exact snake_case params", async () => {
    const client = fakeClient({ data: ROW, error: null });
    const row = await captureAuditEvent(client, {
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
      action: "create",
      resourceType: "app.org_units",
      resourceId: null,
      result: "success",
    });
    assert.equal(client.calls[0]?.fn, "capture_audit_event");
    assert.equal(client.calls[0]?.args.p_correlation_id, null);
    assert.equal(row.action, "create");
  });

  test("falls back to mutation_failed for an unrecognized database error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset by peer" } });
    await assert.rejects(
      () =>
        captureAuditEvent(client, {
          tenantId: TENANT_ID,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
          action: "create",
          resourceType: "app.org_units",
          resourceId: null,
          result: "success",
        }),
      (err: unknown) => {
        assert.ok(err instanceof AuditTrailMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("supremeAdminMutateAuditLog", () => {
  test("classifies insufficient_authority distinctly from audit_log_not_found", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may mutate an existing audit_logs row" } });
    await assert.rejects(
      () => supremeAdminMutateAuditLog(client, { actorAuthUserId: ACTOR_ID, targetId: TARGET_ID, mutationReason: "correction" }),
      (err: unknown) => {
        assert.ok(err instanceof AuditTrailMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("classifies audit_log_not_found", async () => {
    const client = fakeClient({ data: null, error: { message: "audit_log_not_found: no audit_logs row" } });
    await assert.rejects(
      () => supremeAdminMutateAuditLog(client, { actorAuthUserId: ACTOR_ID, targetId: TARGET_ID, mutationReason: "correction" }),
      (err: unknown) => {
        assert.ok(err instanceof AuditTrailMutationError);
        assert.equal(err.code, "audit_log_not_found");
        return true;
      },
    );
  });

  test("calls supreme_admin_mutate_audit_log with the exact snake_case params", async () => {
    const client = fakeClient({ data: ROW, error: null });
    await supremeAdminMutateAuditLog(client, { actorAuthUserId: ACTOR_ID, targetId: TARGET_ID, newLegalHold: true, mutationReason: "litigation hold" });
    assert.equal(client.calls[0]?.fn, "supreme_admin_mutate_audit_log");
    assert.equal(client.calls[0]?.args.p_new_legal_hold, true);
  });
});

describe("supremeAdminDeleteAuditLog", () => {
  test("calls supreme_admin_delete_audit_log and resolves void on success", async () => {
    const client = fakeClient({ data: null, error: null });
    await supremeAdminDeleteAuditLog(client, { actorAuthUserId: ACTOR_ID, targetId: TARGET_ID, reason: "erasure request" });
    assert.equal(client.calls[0]?.fn, "supreme_admin_delete_audit_log");
  });

  test("classifies insufficient_authority on delete", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may delete an audit_logs row" } });
    await assert.rejects(
      () => supremeAdminDeleteAuditLog(client, { actorAuthUserId: ACTOR_ID, targetId: TARGET_ID, reason: "erasure request" }),
      (err: unknown) => {
        assert.ok(err instanceof AuditTrailMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});
