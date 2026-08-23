import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { requestAuditExport, recordAuditExportOutcome, AdvancedAuditMutationError, type AdvancedAuditMutationRpcClient } from "./advanced-audit.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_REQUEST_ROW = {
  id: REQUEST_ID, tenant_id: TENANT_ID, requested_by_auth_user_id: ACTOR_ID, requested_by: "admin1",
  filters: {}, status: "pending", result_row_count: null, result_payload: null, failure_reason: null,
  requested_at: "2026-08-22T00:00:00.000Z", completed_at: null, expires_at: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: AdvancedAuditMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AdvancedAuditMutationRpcClient;
  return { client, calls };
}

describe("requestAuditExport", () => {
  test("calls request_audit_export with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_REQUEST_ROW, error: null });
    const request = await requestAuditExport(client, { tenantId: TENANT_ID, filters: { action: "test" }, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(request.status, "pending");
    assert.deepEqual(calls[0]?.args.p_filters, { action: "test" });
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks authority" } });
    await assert.rejects(
      requestAuditExport(client, { tenantId: TENANT_ID, filters: {}, actorAuthUserId: ACTOR_ID, actorLabel: "viewer1" }),
      (err: unknown) => err instanceof AdvancedAuditMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("recordAuditExportOutcome", () => {
  test("returns the ready request", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_REQUEST_ROW, status: "ready", result_row_count: 3 }, error: null });
    const request = await recordAuditExportOutcome(client, { requestId: REQUEST_ID, status: "ready", resultRowCount: 3, resultPayload: [], failureReason: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(request.status, "ready");
    assert.equal(request.resultRowCount, 3);
  });

  test("classifies audit_export_outcome_already_recorded", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "audit_export_outcome_already_recorded: request already resolved to status ready" } });
    await assert.rejects(
      recordAuditExportOutcome(client, { requestId: REQUEST_ID, status: "failed", resultRowCount: null, resultPayload: null, failureReason: "conflict", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof AdvancedAuditMutationError && err.code === "audit_export_outcome_already_recorded",
    );
  });
});
