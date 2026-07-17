import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  SupportAccessMutationError,
  approveSupportAccess,
  denySupportAccess,
  endSupportSession,
  requestSupportAccess,
  revokeSupportAccess,
  startSupportSession,
  type SupportAccessMutationRpcClient,
} from "./support-access.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const GRANT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SESSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const GRANTEE_ID = "523e4567-e89b-12d3-a456-426614174000";
const APPROVER_ID = "623e4567-e89b-12d3-a456-426614174000";

const GRANT_ROW = {
  id: GRANT_ID,
  tenant_id: TENANT_ID,
  grantee_auth_user_id: GRANTEE_ID,
  reason: "customer cannot see invoices",
  case_id: "CASE-1",
  scope: "read_only",
  emergency: false,
  status: "pending_approval",
  requested_by: "tester",
  requested_at: "2026-07-16T00:00:00.000Z",
  authorized_by_auth_user_id: null,
  approved_by: null,
  granted_at: null,
  denied_by: null,
  denied_at: null,
  denial_reason: null,
  expires_at: "2026-07-16T08:00:00.000Z",
  revoked_at: null,
  revoked_by: null,
  revoked_reason: null,
  post_review_completed_at: null,
  post_review_by: null,
  post_review_note: null,
  record_version: 1,
  created_at: "2026-07-16T00:00:00.000Z",
  updated_at: "2026-07-16T00:00:00.000Z",
};

const SESSION_ROW = {
  id: SESSION_ID,
  grant_id: GRANT_ID,
  tenant_id: TENANT_ID,
  grantee_auth_user_id: GRANTEE_ID,
  reauth_confirmed_at: "2026-07-16T00:05:00.000Z",
  started_at: "2026-07-16T00:05:00.000Z",
  ended_at: null,
  ended_reason: null,
  created_at: "2026-07-16T00:05:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): SupportAccessMutationRpcClient & {
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

describe("requestSupportAccess", () => {
  test("calls request_support_access with the exact snake_case params, defaulting scope/emergency", async () => {
    const client = fakeClient({ data: GRANT_ROW, error: null });
    await requestSupportAccess(client, {
      tenantId: TENANT_ID,
      granteeAuthUserId: GRANTEE_ID,
      reason: "customer cannot see invoices",
      caseId: "CASE-1",
      expiryMinutes: 60,
      requestedBy: "tester",
    });

    assert.equal(client.calls[0]?.fn, "request_support_access");
    assert.equal(client.calls[0]?.args.p_scope, "read_only");
    assert.equal(client.calls[0]?.args.p_emergency, false);
    assert.equal(client.calls[0]?.args.p_authorized_by_auth_user_id, null);
  });

  test("classifies an insufficient_authority rejection (emergency request with no recorded authority) into its typed error code", async () => {
    const client = fakeClient({
      data: null,
      error: { message: "insufficient_authority: emergency support access requires a recorded higher authority" },
    });
    await assert.rejects(
      () =>
        requestSupportAccess(client, {
          tenantId: TENANT_ID,
          granteeAuthUserId: GRANTEE_ID,
          reason: "outage",
          caseId: "CASE-2",
          expiryMinutes: 60,
          requestedBy: "tester",
          emergency: true,
        }),
      (err: unknown) => {
        assert.ok(err instanceof SupportAccessMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized database error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset by peer" } });
    await assert.rejects(
      () =>
        requestSupportAccess(client, {
          tenantId: TENANT_ID,
          granteeAuthUserId: GRANTEE_ID,
          reason: "x",
          caseId: "CASE-3",
          expiryMinutes: 60,
          requestedBy: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof SupportAccessMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("approveSupportAccess", () => {
  test("classifies self_approval_forbidden distinctly from insufficient_authority", async () => {
    const client = fakeClient({ data: null, error: { message: "self_approval_forbidden: identity cannot approve their own support access grant" } });
    await assert.rejects(
      () => approveSupportAccess(client, { grantId: GRANT_ID, approverAuthUserId: GRANTEE_ID, approvedBy: "self" }),
      (err: unknown) => {
        assert.ok(err instanceof SupportAccessMutationError);
        assert.equal(err.code, "self_approval_forbidden");
        return true;
      },
    );
  });

  test("calls approve_support_access with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...GRANT_ROW, status: "approved", granted_at: "2026-07-16T00:05:00.000Z" }, error: null });
    await approveSupportAccess(client, { grantId: GRANT_ID, approverAuthUserId: APPROVER_ID, approvedBy: "tenant admin" });
    assert.equal(client.calls[0]?.fn, "approve_support_access");
    assert.equal(client.calls[0]?.args.p_approver_auth_user_id, APPROVER_ID);
    assert.equal(client.calls[0]?.args.p_expires_at, null);
  });
});

describe("denySupportAccess", () => {
  test("calls deny_support_access with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...GRANT_ROW, status: "denied" }, error: null });
    const grant = await denySupportAccess(client, { grantId: GRANT_ID, denierAuthUserId: APPROVER_ID, deniedBy: "tenant admin", reason: "no valid ticket" });
    assert.equal(grant.status, "denied");
    assert.equal(client.calls[0]?.fn, "deny_support_access");
  });
});

describe("revokeSupportAccess (kill switch)", () => {
  test("calls revoke_support_access with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...GRANT_ROW, status: "revoked" }, error: null });
    const grant = await revokeSupportAccess(client, { grantId: GRANT_ID, revokerAuthUserId: APPROVER_ID, revokedBy: "tenant admin", reason: "incident closed early" });
    assert.equal(grant.status, "revoked");
    assert.equal(client.calls[0]?.fn, "revoke_support_access");
  });
});

describe("startSupportSession", () => {
  test("classifies reauth_required distinctly from grant_expired", async () => {
    const client = fakeClient({ data: null, error: { message: "reauth_required: re-authentication must have completed within the last 5 minutes" } });
    await assert.rejects(
      () => startSupportSession(client, { grantId: GRANT_ID, reauthConfirmedAt: "2020-01-01T00:00:00.000Z", startedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof SupportAccessMutationError);
        assert.equal(err.code, "reauth_required");
        return true;
      },
    );
  });

  test("calls start_support_session with the exact snake_case params", async () => {
    const client = fakeClient({ data: SESSION_ROW, error: null });
    const session = await startSupportSession(client, { grantId: GRANT_ID, reauthConfirmedAt: "2026-07-16T00:05:00.000Z", startedBy: "tester" });
    assert.equal(session.grantId, GRANT_ID);
    assert.equal(client.calls[0]?.fn, "start_support_session");
  });
});

describe("endSupportSession", () => {
  test("defaults endedReason to manual_end", async () => {
    const client = fakeClient({ data: { ...SESSION_ROW, ended_at: "2026-07-16T01:00:00.000Z", ended_reason: "manual_end" }, error: null });
    await endSupportSession(client, { sessionId: SESSION_ID, endedBy: "tester" });
    assert.equal(client.calls[0]?.args.p_ended_reason, "manual_end");
  });

  test("classifies session_not_found", async () => {
    const client = fakeClient({ data: null, error: { message: "session_not_found: no support access session" } });
    await assert.rejects(
      () => endSupportSession(client, { sessionId: SESSION_ID, endedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof SupportAccessMutationError);
        assert.equal(err.code, "session_not_found");
        return true;
      },
    );
  });
});
