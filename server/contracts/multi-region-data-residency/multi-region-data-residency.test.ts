import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseTenantRegionAssignment,
  parseRegionServiceCapability,
  parseRegionCapabilityException,
  RequestRegionAssignmentInputSchema,
  RegisterRegionCapabilityExceptionInputSchema,
  RegionCodeSchema,
} from "./multi-region-data-residency.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseTenantRegionAssignment", () => {
  test("round-trips a pending_review assignment", () => {
    const record = parseTenantRegionAssignment({
      id: ROW_ID, tenant_id: TENANT_ID, region_code: "americas", status: "pending_review",
      qualification_reason: "expansion into the Americas market", contract_reference: "MSA-2026-002",
      approved_by_auth_user_id: null, approved_by: null, approved_at: null, activated_at: null,
      decommissioned_at: null, rejected_at: null, rejection_reason: null,
      created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
    });
    assert.equal(record.status, "pending_review");
    assert.equal(record.regionCode, "americas");
  });

  test("rejects apac as a region assignment's own region_code", () => {
    assert.throws(() =>
      parseTenantRegionAssignment({
        id: ROW_ID, tenant_id: TENANT_ID, region_code: "apac", status: "pending_review",
        qualification_reason: "x", contract_reference: null,
        approved_by_auth_user_id: null, approved_by: null, approved_at: null, activated_at: null,
        decommissioned_at: null, rejected_at: null, rejection_reason: null,
        created_by: null, created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
      }),
    );
  });
});

describe("parseRegionServiceCapability", () => {
  test("round-trips a supported capability row", () => {
    const cap = parseRegionServiceCapability({
      id: ROW_ID, region_code: "apac", service_category: "database", supported: true, notes: "Default region.",
      updated_by_auth_user_id: ACTOR_ID, updated_by: "system", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(cap.supported, true);
    assert.equal(cap.regionCode, "apac");
  });
});

describe("parseRegionCapabilityException", () => {
  test("round-trips an exception row", () => {
    const exception = parseRegionCapabilityException({
      id: ROW_ID, region_assignment_id: ROW_ID, service_category: "database", reason: "accepted risk",
      approved_by_auth_user_id: ACTOR_ID, approved_by: "approver1", approved_at: "2026-08-22T00:00:00.000Z", created_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(exception.serviceCategory, "database");
  });
});

describe("RegionCodeSchema", () => {
  test("accepts apac/americas/emea", () => {
    assert.equal(RegionCodeSchema.parse("apac"), "apac");
    assert.equal(RegionCodeSchema.parse("americas"), "americas");
    assert.equal(RegionCodeSchema.parse("emea"), "emea");
  });

  test("rejects anything else", () => {
    assert.throws(() => RegionCodeSchema.parse("mars"));
  });
});

describe("input schemas", () => {
  test("RequestRegionAssignmentInputSchema rejects an empty qualificationReason", () => {
    assert.throws(() =>
      RequestRegionAssignmentInputSchema.parse({
        tenantId: TENANT_ID, regionCode: "americas", qualificationReason: "", contractReference: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });

  test("RequestRegionAssignmentInputSchema rejects apac as a requested (non-default) region", () => {
    assert.throws(() =>
      RequestRegionAssignmentInputSchema.parse({
        tenantId: TENANT_ID, regionCode: "apac", qualificationReason: "x", contractReference: null, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });

  test("RegisterRegionCapabilityExceptionInputSchema rejects an empty reason", () => {
    assert.throws(() =>
      RegisterRegionCapabilityExceptionInputSchema.parse({
        regionAssignmentId: ROW_ID, serviceCategory: "database", reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "approver1",
      }),
    );
  });
});
