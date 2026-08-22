import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseRetentionPolicy,
  parseLegalHold,
  parseRetentionArchiveRequest,
  SetRetentionPolicyInputSchema,
  RequestLegalHoldInputSchema,
  RequestRetentionArchiveInputSchema,
} from "./data-retention.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseRetentionPolicy", () => {
  test("round-trips a tenant-scoped policy", () => {
    const policy = parseRetentionPolicy({
      id: ROW_ID, tenant_id: TENANT_ID, record_class: "finance_tax", retention_days: 3650,
      created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
    });
    assert.equal(policy.retentionDays, 3650);
  });

  test("rejects an unrecognized record_class", () => {
    assert.throws(() =>
      parseRetentionPolicy({
        id: ROW_ID, tenant_id: TENANT_ID, record_class: "not-a-real-class", retention_days: 90,
        created_by: null, created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
      }),
    );
  });
});

describe("parseLegalHold", () => {
  test("round-trips an active, whole-class hold", () => {
    const hold = parseLegalHold({
      id: ROW_ID, tenant_id: TENANT_ID, record_class: "audit_security", scope_record_table: null, scope_record_id: null,
      reason: "pending litigation", status: "active", placed_by_auth_user_id: ACTOR_ID, placed_by: "admin1",
      placed_at: "2026-08-22T00:00:00.000Z", released_by_auth_user_id: null, released_by: null, released_at: null, release_reason: null,
    });
    assert.equal(hold.status, "active");
    assert.equal(hold.scopeRecordId, null);
  });
});

describe("parseRetentionArchiveRequest", () => {
  test("round-trips a dry-run-completed request", () => {
    const request = parseRetentionArchiveRequest({
      id: ROW_ID, tenant_id: TENANT_ID, record_class: "operational", source_table: "app.some_table", source_record_id: RECORD_ID,
      record_reference_date: "2020-01-01T00:00:00.000Z", dry_run: true, eligible_for_archive_at: "2020-04-01T00:00:00.000Z",
      legal_hold_blocking: false, status: "dry_run_completed", requested_by_auth_user_id: ACTOR_ID, requested_by: "admin1",
      requested_at: "2026-08-22T00:00:00.000Z", completed_at: null, result_note: null,
    });
    assert.equal(request.status, "dry_run_completed");
    assert.equal(request.legalHoldBlocking, false);
  });
});

describe("input schemas", () => {
  test("SetRetentionPolicyInputSchema rejects a non-positive retentionDays", () => {
    assert.throws(() =>
      SetRetentionPolicyInputSchema.parse({ tenantId: TENANT_ID, recordClass: "operational", retentionDays: 0, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
    );
  });

  test("RequestLegalHoldInputSchema rejects an empty reason", () => {
    assert.throws(() =>
      RequestLegalHoldInputSchema.parse({
        tenantId: TENANT_ID, recordClass: "finance_tax", scopeRecordTable: null, scopeRecordId: null, reason: "",
        actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });

  test("RequestRetentionArchiveInputSchema rejects an empty sourceTable", () => {
    assert.throws(() =>
      RequestRetentionArchiveInputSchema.parse({
        tenantId: TENANT_ID, recordClass: "operational", sourceTable: "", sourceRecordId: RECORD_ID,
        recordReferenceDate: "2020-01-01T00:00:00.000Z", dryRun: true, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
      }),
    );
  });
});
