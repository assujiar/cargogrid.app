import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { AuditTrailQueryError, exportAuditLogs, queryAuditLogs, type AuditTrailRpcClient } from "./audit-trail.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REQUESTER_ID = "323e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: "523e4567-e89b-12d3-a456-426614174000",
  correlation_id: "623e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  actor_auth_user_id: REQUESTER_ID,
  actor_label: "tenant admin",
  action: "update",
  resource_type: "app.tenants",
  resource_id: null,
  result: "success",
  reason: null,
  before_value: null,
  after_value: null,
  occurred_at: "2026-07-16T00:00:00.000Z",
  legal_hold: false,
  legal_hold_reason: null,
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): AuditTrailRpcClient & {
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

describe("queryAuditLogs", () => {
  test("calls query_audit_logs with the exact snake_case params, defaulting limit to 50", async () => {
    const client = fakeClient({ data: [ROW], error: null });
    const rows = await queryAuditLogs(client, { requesterAuthUserId: REQUESTER_ID, tenantId: TENANT_ID });
    assert.equal(client.calls[0]?.fn, "query_audit_logs");
    assert.equal(client.calls[0]?.args.p_limit, 50);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.action, "update");
  });

  test("classifies an insufficient_authority rejection into its typed error code", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity holds neither Supreme Admin nor tenant_admin authority" } });
    await assert.rejects(
      () => queryAuditLogs(client, { requesterAuthUserId: REQUESTER_ID, tenantId: TENANT_ID }),
      (err: unknown) => {
        assert.ok(err instanceof AuditTrailQueryError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("throws on a non-array result", async () => {
    const client = fakeClient({ data: { not: "an array" }, error: null });
    await assert.rejects(() => queryAuditLogs(client, { requesterAuthUserId: REQUESTER_ID, tenantId: TENANT_ID }));
  });

  test("returns an empty array (not an error) when no rows match", async () => {
    const client = fakeClient({ data: [], error: null });
    const rows = await queryAuditLogs(client, { requesterAuthUserId: REQUESTER_ID, tenantId: TENANT_ID });
    assert.deepEqual(rows, []);
  });
});

describe("exportAuditLogs", () => {
  test("calls export_audit_logs, not query_audit_logs -- a distinct RPC for a distinct self-audited action label", async () => {
    const client = fakeClient({ data: [ROW], error: null });
    await exportAuditLogs(client, { requesterAuthUserId: REQUESTER_ID, tenantId: TENANT_ID, limit: 500 });
    assert.equal(client.calls[0]?.fn, "export_audit_logs");
    assert.equal(client.calls[0]?.args.p_limit, 500);
  });
});
