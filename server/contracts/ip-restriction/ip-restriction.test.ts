import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseIpAllowlistPolicy,
  parseIpAllowlistEntry,
  parseIpAccessEvaluation,
  parseIpAllowlistBypassGrant,
  SetIpAllowlistEnforcementModeInputSchema,
  AddIpAllowlistEntryInputSchema,
} from "./ip-restriction.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ENTRY_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseIpAllowlistPolicy", () => {
  test("round-trips a dry_run policy", () => {
    const policy = parseIpAllowlistPolicy({ tenant_id: TENANT_ID, enforcement_mode: "dry_run", updated_by: "admin1", updated_at: "2026-08-22T00:00:00.000Z" });
    assert.equal(policy.enforcementMode, "dry_run");
  });

  test("rejects an unrecognized enforcement mode", () => {
    assert.throws(() => parseIpAllowlistPolicy({ tenant_id: TENANT_ID, enforcement_mode: "not-a-real-mode", updated_by: null, updated_at: "2026-08-22T00:00:00.000Z" }));
  });
});

describe("parseIpAllowlistEntry", () => {
  test("round-trips an active IPv4 entry", () => {
    const entry = parseIpAllowlistEntry({
      id: ENTRY_ID, tenant_id: TENANT_ID, cidr: "203.0.113.0/24", label: "office", scope: "all",
      status: "active", created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", revoked_at: null, revoked_by: null,
    });
    assert.equal(entry.cidr, "203.0.113.0/24");
    assert.equal(entry.scope, "all");
  });
});

describe("parseIpAccessEvaluation", () => {
  test("round-trips a dry_run_would_deny evaluation", () => {
    const evaluation = parseIpAccessEvaluation({
      id: ENTRY_ID, tenant_id: TENANT_ID, subject_label: "test-caller", ip_address: "198.51.100.7", scope: "all",
      decision: "dry_run_would_deny", matched_entry_id: null, occurred_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(evaluation.decision, "dry_run_would_deny");
  });
});

describe("parseIpAllowlistBypassGrant", () => {
  test("round-trips a pending grant", () => {
    const grant = parseIpAllowlistBypassGrant({
      id: ENTRY_ID, tenant_id: TENANT_ID, target_auth_user_id: ACTOR_ID, reason: "locked out",
      requested_by_auth_user_id: ACTOR_ID, requested_by: "admin1", approved_by_auth_user_id: null, approved_by: null,
      status: "pending", requested_at: "2026-08-22T00:00:00.000Z", decided_at: null, expires_at: "2026-08-22T02:00:00.000Z",
    });
    assert.equal(grant.status, "pending");
  });
});

describe("input schemas", () => {
  test("SetIpAllowlistEnforcementModeInputSchema rejects an unrecognized mode", () => {
    assert.throws(() =>
      SetIpAllowlistEnforcementModeInputSchema.parse({ tenantId: TENANT_ID, enforcementMode: "not-a-real-mode", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
    );
  });

  test("AddIpAllowlistEntryInputSchema rejects an empty rawCidr", () => {
    assert.throws(() =>
      AddIpAllowlistEntryInputSchema.parse({ tenantId: TENANT_ID, rawCidr: "", label: null, scope: "all", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
    );
  });

  test("AddIpAllowlistEntryInputSchema rejects an unrecognized scope", () => {
    assert.throws(() =>
      AddIpAllowlistEntryInputSchema.parse({ tenantId: TENANT_ID, rawCidr: "203.0.113.0/24", label: null, scope: "not-a-real-scope", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
    );
  });
});
