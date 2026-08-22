import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseExternalSyncEntityMapping,
  parseExternalSyncEntityLink,
  parseExternalSyncRecord,
  parseExternalSyncConnectionForSync,
  SetExternalSyncEntityMappingInputSchema,
  RecordExternalSyncSnapshotInputSchema,
  ReviewExternalSyncConflictInputSchema,
} from "./external-sync.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "423e4567-e89b-12d3-a456-426614174000";
const INTERNAL_RECORD_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseExternalSyncEntityMapping", () => {
  test("maps snake_case columns to camelCase", () => {
    const mapping = parseExternalSyncEntityMapping({
      id: RECORD_ID, tenant_id: TENANT_ID, adapter_code: "external_hr_system", entity_type: "employee",
      ownership_direction: "external_source", status: "active", notes: "HRIS is source during transition", created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(mapping.ownershipDirection, "external_source");
    assert.equal(mapping.entityType, "employee");
  });
});

describe("parseExternalSyncEntityLink", () => {
  test("maps snake_case columns to camelCase", () => {
    const link = parseExternalSyncEntityLink({
      id: RECORD_ID, tenant_id: TENANT_ID, adapter_code: "external_hr_system", entity_type: "employee",
      external_entity_id: "EXT-1", internal_record_id: INTERNAL_RECORD_ID, linked_by_auth_user_id: ACTOR_ID, linked_by: "rep", linked_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(link.externalEntityId, "EXT-1");
    assert.equal(link.internalRecordId, INTERNAL_RECORD_ID);
  });
});

describe("parseExternalSyncRecord", () => {
  test("a matched record with field diffs and a conflict", () => {
    const record = parseExternalSyncRecord({
      id: RECORD_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, entity_type: "employee", external_entity_id: "EXT-1",
      internal_record_id: INTERNAL_RECORD_ID, match_status: "matched", raw_payload: { fullName: "Jane Doe" },
      field_diffs: { fullName: { internal: "Jane D.", external: "Jane Doe" } }, conflict_status: "conflicts_detected",
      review_notes: null, reviewed_by_auth_user_id: null, reviewed_at: null, created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(record.matchStatus, "matched");
    assert.equal(record.conflictStatus, "conflicts_detected");
    assert.deepEqual(record.fieldDiffs, { fullName: { internal: "Jane D.", external: "Jane Doe" } });
  });

  test("an unmatched record carries a null internalRecordId and null fieldDiffs, not a crash", () => {
    const record = parseExternalSyncRecord({
      id: RECORD_ID, tenant_id: TENANT_ID, connection_id: CONNECTION_ID, entity_type: "gl_account", external_entity_id: "EXT-ACCT-1",
      internal_record_id: null, match_status: "unmatched", raw_payload: {}, field_diffs: null, conflict_status: "no_conflict",
      review_notes: null, reviewed_by_auth_user_id: null, reviewed_at: null, created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(record.internalRecordId, null);
    assert.equal(record.fieldDiffs, null);
  });
});

describe("parseExternalSyncConnectionForSync", () => {
  test("maps snake_case columns to camelCase", () => {
    const info = parseExternalSyncConnectionForSync({ tenant_id: TENANT_ID, adapter_code: "external_accounting_system", connection_status: "active", connection_config: { pollUrl: "https://erp.example.test/poll" } });
    assert.equal(info.adapterCode, "external_accounting_system");
  });
});

describe("SetExternalSyncEntityMappingInputSchema", () => {
  test("rejects an unrecognized ownership direction", () => {
    assert.throws(() =>
      SetExternalSyncEntityMappingInputSchema.parse({
        tenantId: TENANT_ID, adapterCode: "external_hr_system", entityType: "employee", ownershipDirection: "external_wins", actorAuthUserId: ACTOR_ID, actorLabel: "system",
      }),
    );
  });

  test("defaults notes to null", () => {
    const parsed = SetExternalSyncEntityMappingInputSchema.parse({
      tenantId: TENANT_ID, adapterCode: "external_hr_system", entityType: "employee", ownershipDirection: "bidirectional", actorAuthUserId: ACTOR_ID, actorLabel: "system",
    });
    assert.equal(parsed.notes, null);
  });
});

describe("RecordExternalSyncSnapshotInputSchema", () => {
  test("rejects an unrecognized entity type", () => {
    assert.throws(() =>
      RecordExternalSyncSnapshotInputSchema.parse({
        tenantId: TENANT_ID, connectionId: CONNECTION_ID, adapterCode: "external_hr_system", entityType: "vendor",
        externalEntityId: "EXT-1", rawPayload: {}, actorAuthUserId: ACTOR_ID, actorLabel: "system",
      }),
    );
  });
});

describe("ReviewExternalSyncConflictInputSchema", () => {
  test("rejects a decision outside reviewed/dismissed", () => {
    assert.throws(() =>
      ReviewExternalSyncConflictInputSchema.parse({
        recordId: RECORD_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "system",
      }),
    );
  });
});
