import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { evaluateTenantBrand, WhiteLabelBrandCache, WhiteLabelQueryError, type WhiteLabelQueryRpcClient } from "./white-label.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";

const TENANT_SOURCE_ROW = {
  tenant_id: TENANT_ID,
  source: "tenant",
  version_id: VERSION_ID,
  version_number: 2,
  tokens: { primary: "#1d4ed8" },
  logo_asset_url: "https://storage.example.test/acme/logo.png",
  email_sender_name: "Acme Logistics",
  email_logo_asset_url: null,
  document_template_refs: {},
  effective_from: "2026-07-17T00:00:00.000Z",
};

const DEFAULT_SOURCE_ROW = {
  tenant_id: TENANT_ID,
  source: "default",
  version_id: null,
  version_number: null,
  tokens: { primary: "#171717", secondary: "#171717" },
  logo_asset_url: null,
  email_sender_name: null,
  email_logo_asset_url: null,
  document_template_refs: {},
  effective_from: null,
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): WhiteLabelQueryRpcClient & { calls: number } {
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

describe("evaluateTenantBrand", () => {
  test("parses a tenant-source row (array response, matching Supabase's table-returning RPC shape)", async () => {
    const client = fakeClient({ data: [TENANT_SOURCE_ROW], error: null });
    const brand = await evaluateTenantBrand(client, { tenantId: TENANT_ID });
    assert.equal(brand.source, "tenant");
    assert.equal(brand.versionId, VERSION_ID);
  });

  test("parses the accessible default fallback (no tenant override published)", async () => {
    const client = fakeClient({ data: [DEFAULT_SOURCE_ROW], error: null });
    const brand = await evaluateTenantBrand(client, { tenantId: TENANT_ID });
    assert.equal(brand.source, "default");
    assert.equal(brand.versionId, null);
    assert.deepEqual(brand.tokens, { primary: "#171717", secondary: "#171717" });
  });

  test("wraps a database error into a typed WhiteLabelQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(
      () => evaluateTenantBrand(client, { tenantId: TENANT_ID }),
      (err: unknown) => {
        assert.ok(err instanceof WhiteLabelQueryError);
        return true;
      },
    );
  });

  test("rejects a malformed tenantId before ever calling the RPC", async () => {
    const client = fakeClient({ data: [TENANT_SOURCE_ROW], error: null });
    await assert.rejects(() => evaluateTenantBrand(client, { tenantId: "not-a-uuid" }));
    assert.equal(client.calls, 0);
  });
});

describe("WhiteLabelBrandCache", () => {
  test("serves a cached decision within the TTL without a second RPC call", async () => {
    const client = fakeClient({ data: [TENANT_SOURCE_ROW], error: null });
    const cache = new WhiteLabelBrandCache(60_000);
    const now = 1_000_000;

    await evaluateTenantBrand(client, { tenantId: TENANT_ID }, cache, now);
    await evaluateTenantBrand(client, { tenantId: TENANT_ID }, cache, now + 1_000);

    assert.equal(client.calls, 1);
  });

  test("re-fetches once the TTL has expired", async () => {
    const client = fakeClient({ data: [TENANT_SOURCE_ROW], error: null });
    const cache = new WhiteLabelBrandCache(60_000);
    const now = 1_000_000;

    await evaluateTenantBrand(client, { tenantId: TENANT_ID }, cache, now);
    await evaluateTenantBrand(client, { tenantId: TENANT_ID }, cache, now + 60_001);

    assert.equal(client.calls, 2);
  });

  test("invalidate() forces a re-fetch on the next call, giving immediate freshness after a publish/rollback", async () => {
    const client = fakeClient({ data: [TENANT_SOURCE_ROW], error: null });
    const cache = new WhiteLabelBrandCache(60_000);
    const now = 1_000_000;

    await evaluateTenantBrand(client, { tenantId: TENANT_ID }, cache, now);
    cache.invalidate(TENANT_ID);
    await evaluateTenantBrand(client, { tenantId: TENANT_ID }, cache, now + 1_000);

    assert.equal(client.calls, 2);
  });
});
