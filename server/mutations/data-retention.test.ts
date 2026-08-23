import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  setRetentionPolicy,
  requestLegalHold,
  releaseLegalHold,
  requestRetentionArchive,
  recordRetentionArchiveOutcome,
  DataRetentionMutationError,
  type DataRetentionMutationRpcClient,
} from "./data-retention.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ROW_ID = "423e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_POLICY_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, record_class: "finance_tax", retention_days: 3650,
  created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", updated_at: "2026-08-22T00:00:00.000Z", record_version: 1,
};

const VALID_HOLD_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, record_class: "audit_security", scope_record_table: null, scope_record_id: null,
  reason: "pending litigation", status: "active", placed_by_auth_user_id: ACTOR_ID, placed_by: "admin1",
  placed_at: "2026-08-22T00:00:00.000Z", released_by_auth_user_id: null, released_by: null, released_at: null, release_reason: null,
};

const VALID_REQUEST_ROW = {
  id: ROW_ID, tenant_id: TENANT_ID, record_class: "operational", source_table: "app.some_table", source_record_id: RECORD_ID,
  record_reference_date: "2020-01-01T00:00:00.000Z", dry_run: false, eligible_for_archive_at: "2020-04-01T00:00:00.000Z",
  legal_hold_blocking: false, status: "pending", requested_by_auth_user_id: ACTOR_ID, requested_by: "admin1",
  requested_at: "2026-08-22T00:00:00.000Z", completed_at: null, result_note: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: DataRetentionMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as DataRetentionMutationRpcClient;
  return { client, calls };
}

describe("setRetentionPolicy", () => {
  test("calls set_retention_policy with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_POLICY_ROW, error: null });
    const policy = await setRetentionPolicy(client, { tenantId: TENANT_ID, recordClass: "finance_tax", retentionDays: 3650, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(policy.retentionDays, 3650);
    assert.equal(calls[0]?.args.p_record_class, "finance_tax");
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks authority" } });
    await assert.rejects(
      setRetentionPolicy(client, { tenantId: TENANT_ID, recordClass: "finance_tax", retentionDays: 3650, actorAuthUserId: ACTOR_ID, actorLabel: "viewer1" }),
      (err: unknown) => err instanceof DataRetentionMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("requestLegalHold / releaseLegalHold", () => {
  test("request returns an active hold", async () => {
    const { client } = fakeRpcClient({ data: VALID_HOLD_ROW, error: null });
    const hold = await requestLegalHold(client, { tenantId: TENANT_ID, recordClass: "audit_security", scopeRecordTable: null, scopeRecordId: null, reason: "pending litigation", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(hold.status, "active");
  });

  test("release classifies insufficient_authority (RET:Approve required)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks RET:Approve" } });
    await assert.rejects(
      releaseLegalHold(client, { holdId: ROW_ID, releaseReason: "litigation resolved", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof DataRetentionMutationError && err.code === "insufficient_authority",
    );
  });

  test("release returns the released hold", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_HOLD_ROW, status: "released", released_at: "2026-08-22T01:00:00.000Z" }, error: null });
    const hold = await releaseLegalHold(client, { holdId: ROW_ID, releaseReason: "litigation resolved", actorAuthUserId: ACTOR_ID, actorLabel: "supreme" });
    assert.equal(hold.status, "released");
  });
});

describe("requestRetentionArchive", () => {
  test("calls request_retention_archive with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_REQUEST_ROW, error: null });
    const request = await requestRetentionArchive(client, {
      tenantId: TENANT_ID, recordClass: "operational", sourceTable: "app.some_table", sourceRecordId: RECORD_ID,
      recordReferenceDate: "2020-01-01T00:00:00.000Z", dryRun: false, actorAuthUserId: ACTOR_ID, actorLabel: "admin1",
    });
    assert.equal(request.status, "pending");
    assert.equal(calls[0]?.args.p_dry_run, false);
  });

  test("classifies retention_archive_invalid_outcome_status via recordRetentionArchiveOutcome", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "retention_archive_invalid_outcome_status: not-a-status is not one of archived/failed" } });
    await assert.rejects(
      recordRetentionArchiveOutcome(client, { requestId: ROW_ID, status: "archived", resultNote: null, actorAuthUserId: ACTOR_ID, actorLabel: "worker" }),
      (err: unknown) => err instanceof DataRetentionMutationError && err.code === "retention_archive_invalid_outcome_status",
    );
  });

  test("recordRetentionArchiveOutcome returns the archived request", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_REQUEST_ROW, status: "archived", completed_at: "2026-08-22T02:00:00.000Z" }, error: null });
    const request = await recordRetentionArchiveOutcome(client, { requestId: ROW_ID, status: "archived", resultNote: "moved to cold storage", actorAuthUserId: ACTOR_ID, actorLabel: "worker" });
    assert.equal(request.status, "archived");
  });
});
