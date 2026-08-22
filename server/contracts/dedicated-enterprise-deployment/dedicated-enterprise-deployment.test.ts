import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseTenantDeploymentRecord,
  parseTenantDeploymentEnvironmentRef,
  RequestDedicatedDeploymentQualificationInputSchema,
  SetDeploymentEnvironmentRefInputSchema,
  ResolvedDeploymentTypeSchema,
} from "./dedicated-enterprise-deployment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseTenantDeploymentRecord", () => {
  test("round-trips a pending_qualification record", () => {
    const record = parseTenantDeploymentRecord({
      id: ROW_ID, tenant_id: TENANT_ID, deployment_type: "dedicated", status: "pending_qualification",
      qualification_reason: "expansion into APAC", contract_reference: "MSA-2026-001",
      approved_by_auth_user_id: null, approved_by: null, approved_at: null, provisioned_at: null, decommissioned_at: null,
      created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
    });
    assert.equal(record.status, "pending_qualification");
    assert.equal(record.deploymentType, "dedicated");
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      parseTenantDeploymentRecord({
        id: ROW_ID, tenant_id: TENANT_ID, deployment_type: "dedicated", status: "not-a-real-status",
        qualification_reason: "x", contract_reference: null,
        approved_by_auth_user_id: null, approved_by: null, approved_at: null, provisioned_at: null, decommissioned_at: null,
        created_by: null, created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
      }),
    );
  });
});

describe("parseTenantDeploymentEnvironmentRef", () => {
  test("round-trips a database environment ref", () => {
    const ref = parseTenantDeploymentEnvironmentRef({
      id: ROW_ID, deployment_record_id: ROW_ID, environment_category: "database", reference_value: "pg-dedicated-01",
      verified_by_auth_user_id: ACTOR_ID, verified_by: "admin1", verified_at: "2026-08-22T00:00:00.000Z",
      created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(ref.environmentCategory, "database");
    assert.equal(ref.referenceValue, "pg-dedicated-01");
  });

  test("rejects an unrecognized environment_category", () => {
    assert.throws(() =>
      parseTenantDeploymentEnvironmentRef({
        id: ROW_ID, deployment_record_id: ROW_ID, environment_category: "not-a-real-category", reference_value: "x",
        verified_by_auth_user_id: null, verified_by: null, verified_at: null, created_by: null, created_at: "2026-08-22T00:00:00.000Z",
      }),
    );
  });
});

describe("ResolvedDeploymentTypeSchema", () => {
  test("accepts shared and dedicated", () => {
    assert.equal(ResolvedDeploymentTypeSchema.parse("shared"), "shared");
    assert.equal(ResolvedDeploymentTypeSchema.parse("dedicated"), "dedicated");
  });

  test("rejects anything else", () => {
    assert.throws(() => ResolvedDeploymentTypeSchema.parse("pending_qualification"));
  });
});

describe("input schemas", () => {
  test("RequestDedicatedDeploymentQualificationInputSchema rejects an empty qualificationReason", () => {
    assert.throws(() =>
      RequestDedicatedDeploymentQualificationInputSchema.parse({
        tenantId: TENANT_ID, qualificationReason: "", contractReference: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });

  test("SetDeploymentEnvironmentRefInputSchema rejects an empty referenceValue", () => {
    assert.throws(() =>
      SetDeploymentEnvironmentRefInputSchema.parse({
        deploymentRecordId: ROW_ID, environmentCategory: "secrets", referenceValue: "", actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });

  test("SetDeploymentEnvironmentRefInputSchema rejects an unrecognized environmentCategory", () => {
    assert.throws(() =>
      SetDeploymentEnvironmentRefInputSchema.parse({
        deploymentRecordId: ROW_ID, environmentCategory: "not-a-real-category", referenceValue: "x", actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });
});
