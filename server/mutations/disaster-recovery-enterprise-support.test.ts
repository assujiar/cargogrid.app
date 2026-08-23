import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  recordDrRestoreTest,
  setSupportEntitlement,
  verifyOnboardingChecklistItem,
  DisasterRecoveryEnterpriseSupportMutationError,
  type DisasterRecoveryEnterpriseSupportMutationRpcClient,
} from "./disaster-recovery-enterprise-support.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_TEST_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, deployment_type: "shared", component_scope: "database", status: "passed",
  observed_rpo_minutes: 30, observed_rto_minutes: 60, failure_reason: null, recovery_steps: null, retest_scheduled_at: null,
  owner_auth_user_id: null, owner_label: null, tested_by_auth_user_id: ACTOR_ID, tested_by: "admin1",
  tested_at: "2026-08-22T00:00:00.000Z", created_at: "2026-08-22T00:00:00.000Z",
};

const VALID_ENTITLEMENT_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, tier: "standard", contract_reference: "MSA-2026-006",
  escalation_contact_name: null, escalation_contact_email: null, p1_response_minutes: null,
  created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
};

const VALID_CHECKLIST_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, sso_verified: false, sso_verified_at: null,
  api_verified: false, api_verified_at: null, integrations_verified: false, integrations_verified_at: null,
  dr_evidence_verified: false, dr_evidence_verified_at: null, support_entitlement_verified: false, support_entitlement_verified_at: null,
  hypercare_plan_acknowledged: false, hypercare_plan_acknowledged_at: null, hypercare_plan_acknowledged_by_auth_user_id: null, hypercare_plan_acknowledged_by: null,
  status: "in_progress", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: DisasterRecoveryEnterpriseSupportMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as DisasterRecoveryEnterpriseSupportMutationRpcClient;
  return { client, calls };
}

describe("recordDrRestoreTest", () => {
  test("calls record_dr_restore_test with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_TEST_ROW, error: null });
    const test1 = await recordDrRestoreTest(client, {
      tenantId: TENANT_ID, deploymentType: "shared", componentScope: "database", status: "passed",
      observedRpoMinutes: 30, observedRtoMinutes: 60, failureReason: null, recoverySteps: null, retestScheduledAt: null,
      ownerAuthUserId: null, ownerLabel: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
    });
    assert.equal(test1.status, "passed");
    assert.equal(calls[0]?.args.p_component_scope, "database");
  });

  test("classifies dr_test_deployment_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "dr_test_deployment_mismatch: tenant does not have an active dedicated deployment" } });
    await assert.rejects(
      recordDrRestoreTest(client, {
        tenantId: TENANT_ID, deploymentType: "dedicated", componentScope: "database", status: "passed",
        observedRpoMinutes: 30, observedRtoMinutes: 60, failureReason: null, recoverySteps: null, retestScheduledAt: null,
        ownerAuthUserId: null, ownerLabel: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
      (err: unknown) => err instanceof DisasterRecoveryEnterpriseSupportMutationError && err.code === "dr_test_deployment_mismatch",
    );
  });

  test("classifies dr_test_failure_evidence_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "dr_test_failure_evidence_required: a real, non-empty failure_reason and recovery_steps must be stated for a failed result" } });
    await assert.rejects(
      recordDrRestoreTest(client, {
        tenantId: TENANT_ID, deploymentType: "shared", componentScope: "database", status: "failed",
        observedRpoMinutes: null, observedRtoMinutes: null, failureReason: "", recoverySteps: "", retestScheduledAt: "2026-09-01T00:00:00.000Z",
        ownerAuthUserId: null, ownerLabel: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
      (err: unknown) => err instanceof DisasterRecoveryEnterpriseSupportMutationError && err.code === "dr_test_failure_evidence_required",
    );
  });

  test("classifies dr_test_retest_schedule_must_be_future", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "dr_test_retest_schedule_must_be_future: retest_scheduled_at must be after the current time" } });
    await assert.rejects(
      recordDrRestoreTest(client, {
        tenantId: TENANT_ID, deploymentType: "shared", componentScope: "database", status: "failed",
        observedRpoMinutes: null, observedRtoMinutes: null, failureReason: "genuine failure", recoverySteps: "genuine steps", retestScheduledAt: "2020-01-01T00:00:00.000Z",
        ownerAuthUserId: null, ownerLabel: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
      (err: unknown) => err instanceof DisasterRecoveryEnterpriseSupportMutationError && err.code === "dr_test_retest_schedule_must_be_future",
    );
  });
});

describe("setSupportEntitlement", () => {
  test("returns a standard entitlement", async () => {
    const { client } = fakeRpcClient({ data: VALID_ENTITLEMENT_ROW, error: null });
    const entitlement = await setSupportEntitlement(client, {
      tenantId: TENANT_ID, tier: "standard", contractReference: "MSA-2026-006", escalationContactName: null,
      escalationContactEmail: null, p1ResponseMinutes: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
    });
    assert.equal(entitlement.tier, "standard");
  });

  test("classifies support_entitlement_24_7_requires_escalation", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "support_entitlement_24_7_requires_escalation: a real escalation_contact_email and a positive p1_response_minutes are required" } });
    await assert.rejects(
      setSupportEntitlement(client, {
        tenantId: TENANT_ID, tier: "enterprise_24_7", contractReference: null, escalationContactName: null,
        escalationContactEmail: null, p1ResponseMinutes: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
      (err: unknown) => err instanceof DisasterRecoveryEnterpriseSupportMutationError && err.code === "support_entitlement_24_7_requires_escalation",
    );
  });
});

describe("verifyOnboardingChecklistItem", () => {
  test("calls verify_onboarding_checklist_item with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_CHECKLIST_ROW, sso_verified: true, sso_verified_at: "2026-08-22T01:00:00.000Z" }, error: null });
    const checklist = await verifyOnboardingChecklistItem(client, { tenantId: TENANT_ID, item: "sso_verified", humanAcknowledged: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(checklist.ssoVerified, true);
    assert.equal(calls[0]?.args.p_item, "sso_verified");
  });

  test("classifies insufficient_authority for the higher-tier hypercare item", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks SUP:Approve" } });
    await assert.rejects(
      verifyOnboardingChecklistItem(client, { tenantId: TENANT_ID, item: "hypercare_plan_acknowledged", humanAcknowledged: true, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof DisasterRecoveryEnterpriseSupportMutationError && err.code === "insufficient_authority",
    );
  });
});
