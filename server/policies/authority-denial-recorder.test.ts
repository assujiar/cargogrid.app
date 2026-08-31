import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  classifyDenial,
  isAuthorityDenial,
  recordAuthorityDenial,
  observeAuthorityDenial,
  type AuthorityDenialRecorderRpcClient,
} from "./authority-denial-recorder.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function stubClient(behaviour: { error?: string; throws?: boolean } = {}) {
  const calls: Record<string, unknown>[] = [];
  const client: AuthorityDenialRecorderRpcClient = {
    async rpc(_fn, args) {
      calls.push(args);
      if (behaviour.throws) throw new Error("network is down");
      return { data: null, error: behaviour.error ? { message: behaviour.error } : null };
    },
  };
  return { client, calls };
}

describe("classifyDenial", () => {
  /**
   * The reason this matters: app.evaluate_permission RETURNS mfa_step_up_required as a decision
   * reason rather than raising, so a step-up refusal reaches the boundary looking like any other
   * insufficient_authority error. If it were not classified apart here, ISS-2026-249's second
   * open producer would be silently folded into the first and nobody would notice.
   */
  test("separates a step-up refusal from an ordinary permission refusal", () => {
    assert.equal(
      classifyDenial("insufficient_authority: identity x lacks FIN:Approve (mfa_step_up_required) for tenant y"),
      "step_up",
    );
    assert.equal(classifyDenial("insufficient_authority: identity x lacks FIN:Approve (role_grant) for tenant y"), "rbac");
  });

  test("recognises an IP-allowlist block", () => {
    assert.equal(classifyDenial("ip_not_allowed: 203.0.113.7 is outside the allowlist"), "ip");
  });
});

describe("isAuthorityDenial", () => {
  test("is true for a refusal and false for an ordinary failure", () => {
    assert.equal(isAuthorityDenial("insufficient_authority: …"), true);
    assert.equal(isAuthorityDenial("insufficient_privilege"), true);
    assert.equal(isAuthorityDenial("mfa_step_up_required: …"), true);
    assert.equal(isAuthorityDenial("stale_version: expected 3 but found 4"), false);
    assert.equal(isAuthorityDenial("check_violation: interval too short"), false);
  });
});

describe("recordAuthorityDenial", () => {
  test("passes every field through under its snake_case RPC name", async () => {
    const { client, calls } = stubClient();
    const written = await recordAuthorityDenial(client, {
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
      kind: "rbac",
      moduleCode: "FIN",
      action: "Approve",
      reason: "insufficient_authority: …",
    });
    assert.equal(written, true);
    assert.equal(calls.length, 1);
    assert.equal(calls[0]?.p_tenant_id, TENANT_ID);
    assert.equal(calls[0]?.p_denial_kind, "rbac");
    assert.equal(calls[0]?.p_module_code, "FIN");
  });

  test("truncates the reason — this column is evidence that a refusal happened, not an essay", async () => {
    const { client, calls } = stubClient();
    await recordAuthorityDenial(client, {
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
      kind: "rbac",
      reason: "x".repeat(2000),
    });
    assert.equal(String(calls[0]?.p_reason).length, 500);
  });

  /**
   * The important guarantee. The user's outcome is already decided by the time this runs — they
   * were refused. Turning a clean refusal into a 500 because an observability write failed would
   * be a strictly worse outcome than losing the row.
   */
  test("never throws, and reports failure, when the RPC errors or the call itself blows up", async () => {
    const errored = stubClient({ error: "tenant_not_found: …" });
    assert.equal(await recordAuthorityDenial(errored.client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, kind: "rbac" }), false);

    const threw = stubClient({ throws: true });
    assert.equal(await recordAuthorityDenial(threw.client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, kind: "rbac" }), false);
  });
});

describe("observeAuthorityDenial", () => {
  test("records a refusal and classifies it from the caught error", async () => {
    const { client, calls } = stubClient();
    await observeAuthorityDenial(
      client,
      { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, moduleCode: "FIN", action: "Approve" },
      new Error("insufficient_authority: identity lacks FIN:Approve (mfa_step_up_required) for tenant"),
    );
    assert.equal(calls.length, 1);
    assert.equal(calls[0]?.p_denial_kind, "step_up");
  });

  /**
   * A stale-version conflict or a check violation is the system working too, but it is not a
   * refusal. Recording those would put ordinary optimistic-concurrency retries into a table whose
   * whole purpose is spotting somebody probing, and the burst detector would then alert on
   * normal use.
   */
  test("stays silent for an ordinary failure that is not a refusal", async () => {
    const { client, calls } = stubClient();
    await observeAuthorityDenial(
      client,
      { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID },
      new Error("stale_version: task expected version 3 but found 4"),
    );
    assert.equal(calls.length, 0);
  });

  test("handles a non-Error rejection without throwing", async () => {
    const { client, calls } = stubClient();
    await observeAuthorityDenial(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }, "insufficient_authority: raw string");
    assert.equal(calls.length, 1);
  });
});
