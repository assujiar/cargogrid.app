import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createProcurementApprovalPolicyVersion,
  publishProcurementApprovalPolicyVersion,
  decideVendorActivationApprovalStep,
  decideRateVersionApprovalStep,
  decideVendorSelectionApprovalStep,
  decideProcurementExceptionApprovalStep,
  createProcurementExceptionRequest,
  cancelProcurementExceptionRequest,
  ProcurementApprovalMutationError,
  type ProcurementApprovalMutationRpcClient,
} from "./procurement-approval.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const POLICY_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "823e4567-e89b-12d3-a456-426614174000";
const ENTITY_ID = "923e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "a23e4567-e89b-12d3-a456-426614174000";
const EXCEPTION_ID = "b23e4567-e89b-12d3-a456-426614174000";
const NOW_ISO = new Date().toISOString();

const VALID_POLICY_ROW = {
  id: POLICY_ID,
  tenant_id: TENANT_ID,
  entity_type: "vendor_activation",
  min_value_amount: null,
  always_required: true,
  status: "draft",
  supersedes_version_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-07T00:00:00.000Z",
  updated_at: "2026-08-07T00:00:00.000Z",
};

const EXCEPTION_ROW = {
  id: EXCEPTION_ID,
  tenant_id: TENANT_ID,
  related_entity_type: "purchase_order",
  related_entity_id: null,
  exception_type: "po_threshold_bypass",
  reason: "emergency spare parts order",
  requested_outcome: null,
  status: "submitted",
  approval_status: "pending",
  approval_request_id: REQUEST_ID,
  idempotency_key: "idem-1",
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-07T00:00:00.000Z",
  updated_at: "2026-08-07T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): ProcurementApprovalMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ProcurementApprovalMutationRpcClient;
}

describe("createProcurementApprovalPolicyVersion", () => {
  test("calls create_procurement_approval_policy_version with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_POLICY_ROW, error: null }, calls);
    const policy = await createProcurementApprovalPolicyVersion(client, { tenantId: TENANT_ID, entityType: "vendor_activation", alwaysRequired: true, actorAuthUserId: ACTOR_ID, createdBy: "tester" });
    assert.equal(calls[0]?.fn, "create_procurement_approval_policy_version");
    assert.equal(calls[0]?.args.p_entity_type, "vendor_activation");
    assert.equal(calls[0]?.args.p_always_required, true);
    assert.equal(policy.status, "draft");
  });

  test("rejects at the contract layer before any rpc round-trip when neither threshold dimension is set", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_POLICY_ROW, error: null }, calls);
    await assert.rejects(() => createProcurementApprovalPolicyVersion(client, { tenantId: TENANT_ID, entityType: "rate_version", actorAuthUserId: ACTOR_ID, createdBy: "tester" }));
    assert.equal(calls.length, 0);
  });

  test("classifies insufficient_authority", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks PRC:Create (missing) for tenant y" } }, []);
    await assert.rejects(
      () => createProcurementApprovalPolicyVersion(client, { tenantId: TENANT_ID, entityType: "vendor_activation", alwaysRequired: true, actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementApprovalMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("publishProcurementApprovalPolicyVersion", () => {
  test("calls publish_procurement_approval_policy_version with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_POLICY_ROW, status: "published" }, error: null }, calls);
    const policy = await publishProcurementApprovalPolicyVersion(client, { policyVersionId: POLICY_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.fn, "publish_procurement_approval_policy_version");
    assert.equal(calls[0]?.args.p_supersedes_version_id, null);
    assert.equal(policy.status, "published");
  });

  test("classifies active_policy_exists", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "active_policy_exists: tenant x already has a published vendor_activation policy" } }, []);
    await assert.rejects(
      () => publishProcurementApprovalPolicyVersion(client, { policyVersionId: POLICY_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementApprovalMutationError);
        assert.equal(err.code, "active_policy_exists");
        return true;
      },
    );
  });
});

describe("decide*ApprovalStep wrappers", () => {
  test("decideVendorActivationApprovalStep calls decide_vendor_activation_approval_step and parses the sync result", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { master_record_id: ENTITY_ID, approval_status: "approved" }, error: null }, calls);
    const result = await decideVendorActivationApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "manager", reauthConfirmedAt: NOW_ISO });
    assert.equal(calls[0]?.fn, "decide_vendor_activation_approval_step");
    assert.equal(calls[0]?.args.p_reauth_confirmed_at, NOW_ISO);
    assert.equal(result.masterRecordId, ENTITY_ID);
    assert.equal(result.approvalStatus, "approved");
  });

  test("decideRateVersionApprovalStep calls decide_rate_version_approval_step and parses governanceApprovalStatus", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { id: ENTITY_ID, governance_approval_status: "rejected" }, error: null }, calls);
    const result = await decideRateVersionApprovalStep(client, { requestStepId: STEP_ID, decision: "rejected", actorAuthUserId: ACTOR_ID, actorLabel: "finance", reauthConfirmedAt: NOW_ISO, reason: "budget exceeded" });
    assert.equal(calls[0]?.fn, "decide_rate_version_approval_step");
    assert.equal(calls[0]?.args.p_reason, "budget exceeded");
    assert.equal(result.governanceApprovalStatus, "rejected");
  });

  test("decideVendorSelectionApprovalStep calls decide_vendor_selection_approval_step", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { id: ENTITY_ID, approval_status: "pending" }, error: null }, calls);
    const result = await decideVendorSelectionApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "manager", reauthConfirmedAt: NOW_ISO });
    assert.equal(calls[0]?.fn, "decide_vendor_selection_approval_step");
    assert.equal(result.approvalStatus, "pending");
  });

  test("decideProcurementExceptionApprovalStep calls decide_procurement_exception_approval_step and parses the full exception request", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...EXCEPTION_ROW, status: "approved", approval_status: "approved" }, error: null }, calls);
    const result = await decideProcurementExceptionApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "finance", reauthConfirmedAt: NOW_ISO });
    assert.equal(calls[0]?.fn, "decide_procurement_exception_approval_step");
    assert.equal(result.status, "approved");
    assert.equal(result.approvalStatus, "approved");
  });

  test("classifies not_a_rate_version_approval", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "not_a_rate_version_approval: approval request x is not a rate version approval" } }, []);
    await assert.rejects(
      () => decideRateVersionApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "manager", reauthConfirmedAt: NOW_ISO }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementApprovalMutationError);
        assert.equal(err.code, "not_a_rate_version_approval");
        return true;
      },
    );
  });

  // Batch 257-259 review (C-18, HIGH): reauthConfirmedAt is now required at the
  // contract layer (Prompt 259 §16's MFA-for-privileged-approvers gate).
  test("rejects a decide-step call missing reauthConfirmedAt", async () => {
    const client = fakeRpcClient({ data: { master_record_id: ENTITY_ID, approval_status: "approved" }, error: null }, []);
    await assert.rejects(() =>
      decideVendorActivationApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "manager" } as never),
    );
  });
});

describe("createProcurementExceptionRequest", () => {
  test("calls create_procurement_exception_request with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: EXCEPTION_ROW, error: null }, calls);
    const req = await createProcurementExceptionRequest(client, {
      tenantId: TENANT_ID,
      exceptionType: "po_threshold_bypass",
      reason: "emergency spare parts order",
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });
    assert.equal(calls[0]?.fn, "create_procurement_exception_request");
    assert.equal(calls[0]?.args.p_related_entity_type, null);
    assert.equal(req.status, "submitted");
  });

  test("classifies idempotency_key_conflict", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "idempotency_key_conflict: key x was already used for a different exception request" } }, []);
    await assert.rejects(
      () =>
        createProcurementExceptionRequest(client, {
          tenantId: TENANT_ID,
          exceptionType: "po_threshold_bypass",
          reason: "a different reason",
          idempotencyKey: "idem-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementApprovalMutationError);
        assert.equal(err.code, "idempotency_key_conflict");
        return true;
      },
    );
  });
});

describe("cancelProcurementExceptionRequest", () => {
  test("calls cancel_procurement_exception_request with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...EXCEPTION_ROW, status: "cancelled" }, error: null }, calls);
    const req = await cancelProcurementExceptionRequest(client, { id: EXCEPTION_ID, expectedVersion: 1, reason: "no longer needed", actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(calls[0]?.fn, "cancel_procurement_exception_request");
    assert.equal(req.status, "cancelled");
  });

  test("classifies invalid_transition", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "invalid_transition: procurement exception request x is approved and cannot be cancelled" } }, []);
    await assert.rejects(
      () => cancelProcurementExceptionRequest(client, { id: EXCEPTION_ID, expectedVersion: 1, reason: "too late", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementApprovalMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});
