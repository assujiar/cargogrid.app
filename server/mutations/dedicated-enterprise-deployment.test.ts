import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  requestDedicatedDeploymentQualification,
  approveDedicatedDeploymentQualification,
  setDeploymentProvisioningStatus,
  setDeploymentEnvironmentRef,
  DedicatedEnterpriseDeploymentMutationError,
  type DedicatedEnterpriseDeploymentMutationRpcClient,
} from "./dedicated-enterprise-deployment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_RECORD_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, deployment_type: "dedicated", status: "pending_qualification",
  qualification_reason: "expansion into APAC", contract_reference: "MSA-2026-001",
  approved_by_auth_user_id: null, approved_by: null, approved_at: null, provisioned_at: null, decommissioned_at: null,
  created_by_auth_user_id: ACTOR_ID, created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
};

const VALID_ENV_REF_ROW = {
  id: ROW_ID, deployment_record_id: ROW_ID, environment_category: "database", reference_value: "pg-dedicated-01",
  verified_by_auth_user_id: ACTOR_ID, verified_by: "admin1", verified_at: "2026-08-22T00:00:00.000Z",
  created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: DedicatedEnterpriseDeploymentMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as DedicatedEnterpriseDeploymentMutationRpcClient;
  return { client, calls };
}

describe("requestDedicatedDeploymentQualification", () => {
  test("calls request_dedicated_deployment_qualification with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_RECORD_ROW, error: null });
    const record = await requestDedicatedDeploymentQualification(client, {
      tenantId: TENANT_ID, qualificationReason: "expansion into APAC", contractReference: "MSA-2026-001", actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
    });
    assert.equal(record.status, "pending_qualification");
    assert.equal(calls[0]?.args.p_qualification_reason, "expansion into APAC");
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks DEPLOY:Configure" } });
    await assert.rejects(
      requestDedicatedDeploymentQualification(client, { tenantId: TENANT_ID, qualificationReason: "x", contractReference: null, actorAuthUserId: ACTOR_ID, actorLabel: "rep1" }),
      (err: unknown) => err instanceof DedicatedEnterpriseDeploymentMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("approveDedicatedDeploymentQualification", () => {
  test("returns a qualified record", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_RECORD_ROW, status: "qualified", approved_by: "approver1", approved_by_auth_user_id: ACTOR_ID, approved_at: "2026-08-22T01:00:00.000Z", record_version: 2 }, error: null });
    const record = await approveDedicatedDeploymentQualification(client, { deploymentRecordId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "approver1" });
    assert.equal(record.status, "qualified");
    assert.equal(record.approvedBy, "approver1");
  });

  test("classifies deployment_record_not_pending_qualification", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "deployment_record_not_pending_qualification: not pending" } });
    await assert.rejects(
      approveDedicatedDeploymentQualification(client, { deploymentRecordId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "approver1" }),
      (err: unknown) => err instanceof DedicatedEnterpriseDeploymentMutationError && err.code === "deployment_record_not_pending_qualification",
    );
  });

  test("classifies deployment_self_approval_forbidden", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "deployment_self_approval_forbidden: identity cannot approve a dedicated deployment qualification they themselves requested" } });
    await assert.rejects(
      approveDedicatedDeploymentQualification(client, { deploymentRecordId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof DedicatedEnterpriseDeploymentMutationError && err.code === "deployment_self_approval_forbidden",
    );
  });
});

describe("setDeploymentProvisioningStatus", () => {
  test("calls set_deployment_provisioning_status with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_RECORD_ROW, status: "provisioning" }, error: null });
    const record = await setDeploymentProvisioningStatus(client, { deploymentRecordId: ROW_ID, newStatus: "provisioning", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(record.status, "provisioning");
    assert.equal(calls[0]?.args.p_new_status, "provisioning");
  });

  test("classifies deployment_invalid_transition", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "deployment_invalid_transition: qualified -> active is not a valid provisioning transition" } });
    await assert.rejects(
      setDeploymentProvisioningStatus(client, { deploymentRecordId: ROW_ID, newStatus: "active", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof DedicatedEnterpriseDeploymentMutationError && err.code === "deployment_invalid_transition",
    );
  });
});

describe("setDeploymentEnvironmentRef", () => {
  test("returns the upserted environment ref", async () => {
    const { client } = fakeRpcClient({ data: VALID_ENV_REF_ROW, error: null });
    const ref = await setDeploymentEnvironmentRef(client, { deploymentRecordId: ROW_ID, environmentCategory: "database", referenceValue: "pg-dedicated-01", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(ref.referenceValue, "pg-dedicated-01");
  });

  test("classifies deployment_invalid_environment_category", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "deployment_invalid_environment_category: not-a-real-category" } });
    await assert.rejects(
      setDeploymentEnvironmentRef(client, { deploymentRecordId: ROW_ID, environmentCategory: "database", referenceValue: "x", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof DedicatedEnterpriseDeploymentMutationError && err.code === "deployment_invalid_environment_category",
    );
  });
});
