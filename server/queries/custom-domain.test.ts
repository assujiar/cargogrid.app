import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listTenantDomains,
  resolveTenantByDomain,
  DomainResolutionCache,
  CustomDomainQueryError,
  type CustomDomainQueryRpcClient,
} from "./custom-domain.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const DOMAIN_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const DOMAIN_ROW = {
  id: DOMAIN_ID,
  tenant_id: TENANT_ID,
  hostname: "shipping.acme.example",
  status: "active",
  verification_method: "dns_txt",
  verification_token: "abc123",
  verification_challenge_host: "_cargogrid-verify.shipping.acme.example",
  requested_by: "tenant admin",
  verified_at: "2026-07-17T00:00:00.000Z",
  verified_by: "tenant admin",
  activated_at: "2026-07-17T01:00:00.000Z",
  activated_by: "tenant admin",
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

const RESOLVED_ROW = { domain_id: DOMAIN_ID, resolved_tenant_id: TENANT_ID, tenant_canonical_status: "active" };

function fakeClient(response: { data: unknown; error: { message: string } | null }): CustomDomainQueryRpcClient & { calls: number } {
  let calls = 0;
  return {
    get calls() {
      return calls;
    },
    async rpc(_fn, _args) {
      calls += 1;
      return response;
    },
  };
}

describe("listTenantDomains", () => {
  test("parses an array of domain rows", async () => {
    const client = fakeClient({ data: [DOMAIN_ROW], error: null });
    const domains = await listTenantDomains(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(domains.length, 1);
    assert.equal(domains[0]?.status, "active");
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity holds neither Supreme Admin nor tenant_admin authority" } });
    await assert.rejects(
      () => listTenantDomains(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof CustomDomainQueryError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("resolveTenantByDomain", () => {
  test("resolves an active domain (array response, matching Supabase's table-returning RPC shape)", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null });
    const resolved = await resolveTenantByDomain(client, { hostname: "shipping.acme.example" });
    assert.equal(resolved?.resolvedTenantId, TENANT_ID);
  });

  test("returns null for a hostname with no active domain (empty array response)", async () => {
    const client = fakeClient({ data: [], error: null });
    const resolved = await resolveTenantByDomain(client, { hostname: "unclaimed.example.test" });
    assert.equal(resolved, null);
  });

  test("lowercases the hostname before calling the RPC (Host header may arrive mixed-case)", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null }) as CustomDomainQueryRpcClient & { calls: number };
    let capturedArgs: Record<string, unknown> | undefined;
    client.rpc = async (fn, args) => {
      capturedArgs = args;
      return { data: [RESOLVED_ROW], error: null };
    };
    await resolveTenantByDomain(client, { hostname: "Shipping.Acme.Example" });
    assert.equal(capturedArgs?.["p_hostname"], "shipping.acme.example");
  });
});

describe("DomainResolutionCache", () => {
  test("caches a positive resolution within the TTL without a second RPC call", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null });
    const cache = new DomainResolutionCache(30_000);
    const now = 1_000_000;

    await resolveTenantByDomain(client, { hostname: "shipping.acme.example" }, cache, now);
    await resolveTenantByDomain(client, { hostname: "shipping.acme.example" }, cache, now + 1_000);

    assert.equal(client.calls, 1);
  });

  test("caches a negative resolution too, distinct from a cache miss", async () => {
    const client = fakeClient({ data: [], error: null });
    const cache = new DomainResolutionCache(30_000);
    const now = 1_000_000;

    const first = await resolveTenantByDomain(client, { hostname: "unclaimed.example.test" }, cache, now);
    const second = await resolveTenantByDomain(client, { hostname: "unclaimed.example.test" }, cache, now + 1_000);

    assert.equal(first, null);
    assert.equal(second, null);
    assert.equal(client.calls, 1);
  });

  test("invalidate() forces a re-fetch on the next call, giving immediate freshness after activate/disable", async () => {
    const client = fakeClient({ data: [RESOLVED_ROW], error: null });
    const cache = new DomainResolutionCache(30_000);
    const now = 1_000_000;

    await resolveTenantByDomain(client, { hostname: "shipping.acme.example" }, cache, now);
    cache.invalidate("shipping.acme.example");
    await resolveTenantByDomain(client, { hostname: "shipping.acme.example" }, cache, now + 1_000);

    assert.equal(client.calls, 2);
  });
});
