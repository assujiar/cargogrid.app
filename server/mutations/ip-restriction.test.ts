import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  setIpAllowlistEnforcementMode,
  addIpAllowlistEntry,
  revokeIpAllowlistEntry,
  assertIpAllowed,
  evaluateIpAccess,
  requestIpAllowlistBypass,
  approveIpAllowlistBypass,
  IpRestrictionMutationError,
  type IpRestrictionMutationRpcClient,
} from "./ip-restriction.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const ENTRY_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_POLICY_ROW = { tenant_id: TENANT_ID, enforcement_mode: "dry_run", updated_by: "admin1", updated_at: "2026-08-22T00:00:00.000Z" };

const VALID_ENTRY_ROW = {
  id: ENTRY_ID, tenant_id: TENANT_ID, cidr: "203.0.113.0/24", label: "office", scope: "all",
  status: "active", created_by: "admin1", created_at: "2026-08-22T00:00:00.000Z", revoked_at: null, revoked_by: null,
};

const VALID_GRANT_ROW = {
  id: ENTRY_ID, tenant_id: TENANT_ID, target_auth_user_id: ACTOR_ID, reason: "locked out",
  requested_by_auth_user_id: ACTOR_ID, requested_by: "admin1", approved_by_auth_user_id: null, approved_by: null,
  status: "pending", requested_at: "2026-08-22T00:00:00.000Z", decided_at: null, expires_at: "2026-08-22T02:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: IpRestrictionMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as IpRestrictionMutationRpcClient;
  return { client, calls };
}

describe("setIpAllowlistEnforcementMode", () => {
  test("calls set_ip_allowlist_enforcement_mode with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_POLICY_ROW, error: null });
    const policy = await setIpAllowlistEnforcementMode(client, { tenantId: TENANT_ID, enforcementMode: "dry_run", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(policy.enforcementMode, "dry_run");
    assert.equal(calls[0]?.args.p_enforcement_mode, "dry_run");
  });

  test("classifies the lockout guard's own named error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "ip_allowlist_no_active_entries: cannot enforce with zero active allowlist entries" } });
    await assert.rejects(
      setIpAllowlistEnforcementMode(client, { tenantId: TENANT_ID, enforcementMode: "enforced", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof IpRestrictionMutationError && err.code === "ip_allowlist_no_active_entries",
    );
  });
});

describe("addIpAllowlistEntry / revokeIpAllowlistEntry", () => {
  test("add returns a real entry", async () => {
    const { client } = fakeRpcClient({ data: VALID_ENTRY_ROW, error: null });
    const entry = await addIpAllowlistEntry(client, { tenantId: TENANT_ID, rawCidr: "203.0.113.0/24", label: "office", scope: "all", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(entry.cidr, "203.0.113.0/24");
  });

  test("add classifies an invalid CIDR", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "ip_allowlist_invalid_cidr: not-a-cidr is not a well-formed IPv4/IPv6 CIDR" } });
    await assert.rejects(
      addIpAllowlistEntry(client, { tenantId: TENANT_ID, rawCidr: "not-a-cidr", label: null, scope: "all", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof IpRestrictionMutationError && err.code === "ip_allowlist_invalid_cidr",
    );
  });

  test("revoke returns the revoked entry", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_ENTRY_ROW, status: "revoked" }, error: null });
    const entry = await revokeIpAllowlistEntry(client, { entryId: ENTRY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(entry.status, "revoked");
  });
});

describe("assertIpAllowed", () => {
  test("resolves (no throw) when the RPC reports no error", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await assertIpAllowed(client, { tenantId: TENANT_ID, rawIpAddress: "203.0.113.42", scope: "all", subjectLabel: "test-caller" });
    assert.equal(calls[0]?.fn, "assert_ip_allowed");
  });

  test("throws ip_not_allowed when the RPC reports that error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "ip_not_allowed: 198.51.100.7 is not in any active allowlist entry" } });
    await assert.rejects(
      assertIpAllowed(client, { tenantId: TENANT_ID, rawIpAddress: "198.51.100.7", scope: "all", subjectLabel: "test-caller" }),
      (err: unknown) => err instanceof IpRestrictionMutationError && err.code === "ip_not_allowed",
    );
  });
});

describe("evaluateIpAccess (ISS-2026-307)", () => {
  test("returns the decision instead of throwing, so a denial can be recorded and acted on", async () => {
    const { client, calls } = fakeRpcClient({ data: "denied", error: null });
    const decision = await evaluateIpAccess(client, { tenantId: TENANT_ID, rawIpAddress: "198.51.100.7", scope: "admin", subjectLabel: "test-caller" });
    assert.equal(decision, "denied");
    assert.equal(calls[0]?.fn, "evaluate_ip_access");
  });

  test("distinguishes not_enforced from allowed", async () => {
    // A tenant with the control switched off has not been checked. Collapsing that into
    // "allowed" would put a decision in the audit trail that nobody actually made.
    const { client } = fakeRpcClient({ data: "not_enforced", error: null });
    assert.equal(
      await evaluateIpAccess(client, { tenantId: TENANT_ID, rawIpAddress: "198.51.100.7", scope: "admin", subjectLabel: "t" }),
      "not_enforced",
    );
  });

  test("fails loudly rather than open on an unrecognized decision", async () => {
    // The failure mode that matters for an access-control primitive: if the database ever
    // returns something this layer does not understand, it must not be treated as a pass.
    const { client } = fakeRpcClient({ data: "probably_fine", error: null });
    await assert.rejects(
      evaluateIpAccess(client, { tenantId: TENANT_ID, rawIpAddress: "198.51.100.7", scope: "admin", subjectLabel: "t" }),
      (err: unknown) => err instanceof IpRestrictionMutationError && err.code === "invalid_response",
    );
  });

  test("surfaces an RPC error rather than swallowing it into a decision", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: nope" } });
    await assert.rejects(
      evaluateIpAccess(client, { tenantId: TENANT_ID, rawIpAddress: "198.51.100.7", scope: "admin", subjectLabel: "t" }),
      (err: unknown) => err instanceof IpRestrictionMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("requestIpAllowlistBypass / approveIpAllowlistBypass", () => {
  test("request returns a pending grant", async () => {
    const { client } = fakeRpcClient({ data: VALID_GRANT_ROW, error: null });
    const grant = await requestIpAllowlistBypass(client, { tenantId: TENANT_ID, targetAuthUserId: ACTOR_ID, reason: "locked out", actorAuthUserId: ACTOR_ID, actorLabel: "admin1" });
    assert.equal(grant.status, "pending");
  });

  test("approve classifies self-approval-forbidden", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "ip_bypass_self_approval_forbidden: identity cannot approve their own request" } });
    await assert.rejects(
      approveIpAllowlistBypass(client, { grantId: ENTRY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "admin1" }),
      (err: unknown) => err instanceof IpRestrictionMutationError && err.code === "ip_bypass_self_approval_forbidden",
    );
  });

  test("approve returns the approved grant", async () => {
    const { client } = fakeRpcClient({ data: { ...VALID_GRANT_ROW, status: "approved" }, error: null });
    const grant = await approveIpAllowlistBypass(client, { grantId: ENTRY_ID, actorAuthUserId: ACTOR_ID, actorLabel: "supreme" });
    assert.equal(grant.status, "approved");
  });
});
