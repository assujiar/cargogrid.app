import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  requestTenantDomain,
  verifyTenantDomain,
  activateTenantDomain,
  disableTenantDomain,
  rejectTenantDomain,
  CustomDomainMutationError,
  type CustomDomainMutationRpcClient,
} from "./custom-domain.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const DOMAIN_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_ROW = {
  id: DOMAIN_ID,
  tenant_id: TENANT_ID,
  hostname: "shipping.acme.example",
  status: "pending_verification",
  verification_method: "dns_txt",
  verification_token: "abc123",
  verification_challenge_host: "_cargogrid-verify.shipping.acme.example",
  requested_by: "tenant admin",
  verified_at: null,
  verified_by: null,
  activated_at: null,
  activated_by: null,
  disabled_at: null,
  disabled_by: null,
  disabled_reason: null,
  rejected_at: null,
  rejected_by: null,
  rejected_reason: null,
  expires_at: "2026-07-24T00:00:00.000Z",
  record_version: 1,
  created_at: "2026-07-17T00:00:00.000Z",
  updated_at: "2026-07-17T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): CustomDomainMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("requestTenantDomain", () => {
  test("calls request_tenant_domain with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    await requestTenantDomain(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, hostname: "shipping.acme.example", requestedBy: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_hostname: "shipping.acme.example",
      p_requested_by: "tenant admin",
    });
  });

  test("wraps a domain_already_claimed error into a typed CustomDomainMutationError", async () => {
    const client = fakeClient({ data: null, error: { message: "domain_already_claimed: shipping.acme.example is already claimed by another tenant" } });
    await assert.rejects(
      () => requestTenantDomain(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, hostname: "shipping.acme.example", requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomDomainMutationError);
        assert.equal(err.code, "domain_already_claimed");
        return true;
      },
    );
  });

  test("wraps a reserved_hostname error", async () => {
    const client = fakeClient({ data: null, error: { message: "reserved_hostname: cargogrid.app is a reserved platform hostname and cannot be claimed" } });
    await assert.rejects(
      () => requestTenantDomain(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, hostname: "cargogrid.app", requestedBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomDomainMutationError);
        assert.equal(err.code, "reserved_hostname");
        return true;
      },
    );
  });
});

describe("verifyTenantDomain", () => {
  test("calls verify_tenant_domain with the exact snake_case params", async () => {
    const verifiedRow = { ...VALID_ROW, status: "verified", verified_by: "tenant admin" };
    const client = fakeClient({ data: verifiedRow, error: null });
    const domain = await verifyTenantDomain(client, { domainId: DOMAIN_ID, actorAuthUserId: ACTOR_ID, observedTxtValue: "abc123", verifiedBy: "tenant admin" });

    assert.equal(client.calls[0]?.fn, "verify_tenant_domain");
    assert.equal(domain.status, "verified");
  });

  test("wraps a verification_token_mismatch error", async () => {
    const client = fakeClient({ data: null, error: { message: "verification_token_mismatch: observed TXT value does not match the issued challenge token" } });
    await assert.rejects(
      () => verifyTenantDomain(client, { domainId: DOMAIN_ID, actorAuthUserId: ACTOR_ID, observedTxtValue: "wrong", verifiedBy: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomDomainMutationError);
        assert.equal(err.code, "verification_token_mismatch");
        return true;
      },
    );
  });

  test("wraps a verification_expired error", async () => {
    const client = fakeClient({ data: null, error: { message: "verification_expired: domain challenge expired" } });
    await assert.rejects(
      () => verifyTenantDomain(client, { domainId: DOMAIN_ID, actorAuthUserId: ACTOR_ID, observedTxtValue: "abc123", verifiedBy: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomDomainMutationError);
        assert.equal(err.code, "verification_expired");
        return true;
      },
    );
  });
});

describe("activateTenantDomain", () => {
  test("calls activate_tenant_domain with the exact snake_case params", async () => {
    const activeRow = { ...VALID_ROW, status: "active", activated_by: "tenant admin" };
    const client = fakeClient({ data: activeRow, error: null });
    const domain = await activateTenantDomain(client, { domainId: DOMAIN_ID, actorAuthUserId: ACTOR_ID, activatedBy: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, { p_domain_id: DOMAIN_ID, p_actor_auth_user_id: ACTOR_ID, p_activated_by: "tenant admin" });
    assert.equal(domain.status, "active");
  });

  test("wraps a domain_not_verified error", async () => {
    const client = fakeClient({ data: null, error: { message: "domain_not_verified: domain is pending_verification, only a verified domain may be activated" } });
    await assert.rejects(
      () => activateTenantDomain(client, { domainId: DOMAIN_ID, actorAuthUserId: ACTOR_ID, activatedBy: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof CustomDomainMutationError);
        assert.equal(err.code, "domain_not_verified");
        return true;
      },
    );
  });
});

describe("disableTenantDomain", () => {
  test("calls disable_tenant_domain with the exact snake_case params", async () => {
    const disabledRow = { ...VALID_ROW, status: "disabled", disabled_reason: "billing hold" };
    const client = fakeClient({ data: disabledRow, error: null });
    await disableTenantDomain(client, { domainId: DOMAIN_ID, actorAuthUserId: ACTOR_ID, reason: "billing hold", disabledBy: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_domain_id: DOMAIN_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_reason: "billing hold",
      p_disabled_by: "tenant admin",
    });
  });
});

describe("rejectTenantDomain", () => {
  test("calls reject_tenant_domain with the exact snake_case params", async () => {
    const rejectedRow = { ...VALID_ROW, status: "rejected", rejected_reason: "suspicious hostname" };
    const client = fakeClient({ data: rejectedRow, error: null });
    const domain = await rejectTenantDomain(client, { domainId: DOMAIN_ID, actorAuthUserId: ACTOR_ID, reason: "suspicious hostname", rejectedBy: "supreme admin" });

    assert.equal(domain.status, "rejected");
    assert.equal(client.calls[0]?.fn, "reject_tenant_domain");
  });
});
