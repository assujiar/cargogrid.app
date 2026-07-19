import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  publishApprovalDefinition,
  requestApproval,
  decideApprovalStep,
  cancelApprovalRequest,
  escalateApprovalStep,
  createApprovalDelegation,
  revokeApprovalDelegation,
  ApprovalMutationError,
  type ApprovalMutationRpcClient,
} from "./approval.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "723e4567-e89b-12d3-a456-426614174000";
const ROLE_ID = "823e4567-e89b-12d3-a456-426614174000";
const DELEGATE_ID = "923e4567-e89b-12d3-a456-426614174000";
const DELEGATION_ID = "a23e4567-e89b-12d3-a456-426614174000";

const VALID_VERSION_ROW = {
  id: VERSION_ID,
  config_object_id: OBJECT_ID,
  version_number: 1,
  status: "published",
  effective_from: "2026-07-19T00:00:00.000Z",
  effective_to: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  created_by: "tenant admin",
  published_by: "tenant admin",
  published_at: "2026-07-19T00:00:00.000Z",
  archived_at: null,
  archived_reason: null,
  record_version: 2,
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_REQUEST_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  config_version_id: VERSION_ID,
  entity_type: "generic",
  entity_id: null,
  pattern: "sequential",
  status: "pending",
  idempotency_key: "req-9001",
  requested_by_auth_user_id: ACTOR_ID,
  requested_by: "tenant user",
  started_at: "2026-07-19T00:00:00.000Z",
  ended_at: null,
  ended_reason: null,
  record_version: 1,
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_STEP_ROW = {
  id: STEP_ID,
  request_id: REQUEST_ID,
  step_order: 1,
  approver_type: "role",
  role_id: ROLE_ID,
  specific_user_id: null,
  required_approvals: 1,
  approvals_count: 0,
  status: "active",
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

const VALID_DELEGATION_ROW = {
  id: DELEGATION_ID,
  tenant_id: TENANT_ID,
  delegator_auth_user_id: ACTOR_ID,
  delegate_auth_user_id: DELEGATE_ID,
  scope: "all",
  role_id: null,
  starts_at: "2026-07-19T00:00:00.000Z",
  expires_at: "2026-08-19T00:00:00.000Z",
  created_by: "tenant admin",
  created_at: "2026-07-19T00:00:00.000Z",
  revoked_at: null,
  revoked_reason: null,
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): ApprovalMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("publishApprovalDefinition", () => {
  test("calls publish_approval_definition and returns the published version row", async () => {
    const client = fakeClient({ data: VALID_VERSION_ROW, error: null });
    const version = await publishApprovalDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(version.status, "published");
    assert.equal(client.calls[0]?.fn, "publish_approval_definition");
  });

  test("wraps an approval_missing_steps error", async () => {
    const client = fakeClient({ data: null, error: { message: "approval_missing_steps: version x has no 'steps' item" } });
    await assert.rejects(
      () => publishApprovalDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ApprovalMutationError);
        assert.equal(err.code, "approval_missing_steps");
        return true;
      },
    );
  });
});

describe("requestApproval", () => {
  test("calls request_approval with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_REQUEST_ROW, error: null });
    const request = await requestApproval(client, {
      configVersionId: VERSION_ID,
      tenantId: TENANT_ID,
      entityType: "generic",
      entityId: null,
      idempotencyKey: "req-9001",
      actorAuthUserId: ACTOR_ID,
      requestedBy: "tenant user",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_config_version_id: VERSION_ID,
      p_tenant_id: TENANT_ID,
      p_entity_type: "generic",
      p_entity_id: null,
      p_idempotency_key: "req-9001",
      p_actor_auth_user_id: ACTOR_ID,
      p_requested_by: "tenant user",
    });
    assert.equal(request.status, "pending");
  });

  test("wraps an approval_no_eligible_approver error", async () => {
    const client = fakeClient({ data: null, error: { message: "approval_no_eligible_approver: step 1 has zero currently-eligible approvers" } });
    await assert.rejects(
      () =>
        requestApproval(client, {
          configVersionId: VERSION_ID,
          tenantId: TENANT_ID,
          idempotencyKey: "req-9001",
          actorAuthUserId: ACTOR_ID,
          requestedBy: "tenant user",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ApprovalMutationError);
        assert.equal(err.code, "approval_no_eligible_approver");
        return true;
      },
    );
  });
});

describe("decideApprovalStep", () => {
  test("calls decide_approval_step and returns the updated step", async () => {
    const approvedRow = { ...VALID_STEP_ROW, status: "approved", approvals_count: 1 };
    const client = fakeClient({ data: approvedRow, error: null });
    const step = await decideApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "manager" });
    assert.equal(step.status, "approved");
  });

  test("wraps an approval_self_approval_denied error", async () => {
    const client = fakeClient({ data: null, error: { message: "approval_self_approval_denied: identity x requested this approval" } });
    await assert.rejects(
      () => decideApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "manager" }),
      (err: unknown) => {
        assert.ok(err instanceof ApprovalMutationError);
        assert.equal(err.code, "approval_self_approval_denied");
        return true;
      },
    );
  });

  test("wraps an approval_decision_already_recorded error", async () => {
    const client = fakeClient({ data: null, error: { message: "approval_decision_already_recorded: identity x has already decided step y" } });
    await assert.rejects(
      () => decideApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "manager" }),
      (err: unknown) => {
        assert.ok(err instanceof ApprovalMutationError);
        assert.equal(err.code, "approval_decision_already_recorded");
        return true;
      },
    );
  });
});

describe("cancelApprovalRequest", () => {
  test("calls cancel_approval_request with the exact snake_case params", async () => {
    const cancelledRow = { ...VALID_REQUEST_ROW, status: "cancelled", ended_reason: "duplicate request" };
    const client = fakeClient({ data: cancelledRow, error: null });
    const request = await cancelApprovalRequest(client, { requestId: REQUEST_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant user", reason: "duplicate request" });

    assert.deepEqual(client.calls[0]?.args, {
      p_request_id: REQUEST_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tenant user",
      p_reason: "duplicate request",
    });
    assert.equal(request.status, "cancelled");
  });
});

describe("escalateApprovalStep", () => {
  test("calls escalate_approval_step with the exact snake_case params", async () => {
    const escalatedRow = { ...VALID_STEP_ROW, specific_user_id: DELEGATE_ID, role_id: null, approver_type: "specific_user" };
    const client = fakeClient({ data: escalatedRow, error: null });
    const step = await escalateApprovalStep(client, {
      requestStepId: STEP_ID,
      newApproverType: "specific_user",
      newSpecificUserId: DELEGATE_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tenant admin",
      reason: "SLA breach",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_request_step_id: STEP_ID,
      p_new_approver_type: "specific_user",
      p_new_role_id: null,
      p_new_specific_user_id: DELEGATE_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tenant admin",
      p_reason: "SLA breach",
    });
    assert.equal(step.approverType, "specific_user");
  });
});

describe("createApprovalDelegation", () => {
  test("calls create_approval_delegation with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_DELEGATION_ROW, error: null });
    await createApprovalDelegation(client, {
      tenantId: TENANT_ID,
      delegatorAuthUserId: ACTOR_ID,
      delegateAuthUserId: DELEGATE_ID,
      expiresAt: "2026-08-19T00:00:00.000Z",
      actorAuthUserId: ACTOR_ID,
      createdBy: "tenant admin",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_delegator_auth_user_id: ACTOR_ID,
      p_delegate_auth_user_id: DELEGATE_ID,
      p_scope: "all",
      p_role_id: null,
      p_starts_at: null,
      p_expires_at: "2026-08-19T00:00:00.000Z",
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "tenant admin",
    });
  });
});

describe("revokeApprovalDelegation", () => {
  test("wraps an approval_delegation_already_revoked error", async () => {
    const client = fakeClient({ data: null, error: { message: "approval_delegation_already_revoked: delegation x was already revoked" } });
    await assert.rejects(
      () => revokeApprovalDelegation(client, { delegationId: DELEGATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin", reason: "no longer needed" }),
      (err: unknown) => {
        assert.ok(err instanceof ApprovalMutationError);
        assert.equal(err.code, "approval_delegation_already_revoked");
        return true;
      },
    );
  });
});
