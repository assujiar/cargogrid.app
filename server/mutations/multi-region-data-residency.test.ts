import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  setRegionServiceCapability,
  requestRegionAssignment,
  approveRegionAssignment,
  registerRegionCapabilityException,
  setRegionAssignmentStatus,
  MultiRegionDataResidencyMutationError,
  type MultiRegionDataResidencyMutationRpcClient,
} from "./multi-region-data-residency.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_CAPABILITY_ROW = {
  id: ROW_ID, region_code: "americas", service_category: "ai_provider", supported: true, notes: "provider capacity now available",
  updated_by_auth_user_id: ACTOR_ID, updated_by: "supreme", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z",
};

const VALID_ASSIGNMENT_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, region_code: "americas", status: "pending_review",
  qualification_reason: "expansion into the Americas market", contract_reference: "MSA-2026-002",
  approved_by_auth_user_id: null, approved_by: null, approved_at: null, activated_at: null,
  decommissioned_at: null, rejected_at: null, rejection_reason: null,
  created_by_auth_user_id: ACTOR_ID, created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
};

const VALID_EXCEPTION_ROW = {
  id: ROW_ID, region_assignment_id: ROW_ID, service_category: "database", reason: "accepted risk pending regional buildout",
  approved_by_auth_user_id: ACTOR_ID, approved_by: "approver1", approved_at: "2026-08-22T00:00:00.000Z", created_at: "2026-08-22T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: MultiRegionDataResidencyMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as MultiRegionDataResidencyMutationRpcClient;
  return { client, calls };
}

describe("setRegionServiceCapability", () => {
  test("calls set_region_service_capability with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_CAPABILITY_ROW, error: null });
    const cap = await setRegionServiceCapability(client, { regionCode: "americas", serviceCategory: "ai_provider", supported: true, notes: "provider capacity now available", actorAuthUserId: ACTOR_ID, actorLabel: "supreme" });
    assert.equal(cap.supported, true);
    assert.equal(calls[0]?.args.p_region_code, "americas");
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity is not a Supreme Admin" } });
    await assert.rejects(
      setRegionServiceCapability(client, { regionCode: "americas", serviceCategory: "ai_provider", supported: true, notes: null, actorAuthUserId: ACTOR_ID, actorLabel: "viewer1" }),
      (err: unknown) => err instanceof MultiRegionDataResidencyMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("requestRegionAssignment", () => {
  test("returns a pending_review assignment", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_ASSIGNMENT_ROW, error: null });
    const record = await requestRegionAssignment(client, { tenantId: TENANT_ID, regionCode: "americas", qualificationReason: "expansion into the Americas market", contractReference: "MSA-2026-002", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(record.status, "pending_review");
    assert.equal(calls[0]?.args.p_region_code, "americas");
  });
});

describe("approveRegionAssignment", () => {
  test("classifies region_requires_dedicated_deployment", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "region_requires_dedicated_deployment: tenant has no active dedicated deployment" } });
    await assert.rejects(
      approveRegionAssignment(client, { regionAssignmentId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "approver1" }),
      (err: unknown) => err instanceof MultiRegionDataResidencyMutationError && err.code === "region_requires_dedicated_deployment",
    );
  });

  test("classifies region_capability_gap_unresolved", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "region_capability_gap_unresolved: database is not supported in americas and no exception has been registered" } });
    await assert.rejects(
      approveRegionAssignment(client, { regionAssignmentId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "approver1" }),
      (err: unknown) => err instanceof MultiRegionDataResidencyMutationError && err.code === "region_capability_gap_unresolved",
    );
  });

  test("returns an approved assignment", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_ASSIGNMENT_ROW, status: "approved", approved_by: "approver1", approved_by_auth_user_id: ACTOR_ID, approved_at: "2026-08-22T01:00:00.000Z", record_version: 2 }, error: null });
    const record = await approveRegionAssignment(client, { regionAssignmentId: ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "approver1" });
    assert.equal(record.status, "approved");
  });
});

describe("registerRegionCapabilityException", () => {
  test("returns the registered exception", async () => {
    const { client } = fakeRpcClient({ data: VALID_EXCEPTION_ROW, error: null });
    const exception = await registerRegionCapabilityException(client, { regionAssignmentId: ROW_ID, serviceCategory: "database", reason: "accepted risk pending regional buildout", actorAuthUserId: ACTOR_ID, actorLabel: "approver1" });
    assert.equal(exception.serviceCategory, "database");
  });

  test("classifies region_capability_exception_not_needed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "region_capability_exception_not_needed: ai_provider is already supported in americas -- no exception is meaningful" } });
    await assert.rejects(
      registerRegionCapabilityException(client, { regionAssignmentId: ROW_ID, serviceCategory: "ai_provider", reason: "should not be needed", actorAuthUserId: ACTOR_ID, actorLabel: "approver1" }),
      (err: unknown) => err instanceof MultiRegionDataResidencyMutationError && err.code === "region_capability_exception_not_needed",
    );
  });
});

describe("setRegionAssignmentStatus", () => {
  test("calls set_region_assignment_status with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_ASSIGNMENT_ROW, status: "active" }, error: null });
    const record = await setRegionAssignmentStatus(client, { regionAssignmentId: ROW_ID, newStatus: "active", rejectionReason: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(record.status, "active");
    assert.equal(calls[0]?.args.p_new_status, "active");
  });

  test("classifies region_invalid_transition", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "region_invalid_transition: approved -> decommissioned is not a valid region assignment transition" } });
    await assert.rejects(
      setRegionAssignmentStatus(client, { regionAssignmentId: ROW_ID, newStatus: "decommissioned", rejectionReason: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof MultiRegionDataResidencyMutationError && err.code === "region_invalid_transition",
    );
  });

  test("classifies region_rejection_reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "region_rejection_reason_required: a real rejection reason must be stated" } });
    await assert.rejects(
      setRegionAssignmentStatus(client, { regionAssignmentId: ROW_ID, newStatus: "rejected", rejectionReason: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof MultiRegionDataResidencyMutationError && err.code === "region_rejection_reason_required",
    );
  });
});
