import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveLocaleContext, LocaleContextCache, LocalizationQueryError, type LocalizationQueryRpcClient } from "./localization.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const USER_ID = "323e4567-e89b-12d3-a456-426614174000";

const TENANT_SOURCE_ROW = {
  tenant_id: TENANT_ID,
  source: "tenant",
  locale: "en",
  timezone: "UTC",
  currency: "USD",
  terminology_overrides: { "tenant_status.active": "Live" },
};

const DEFAULT_SOURCE_ROW = {
  tenant_id: TENANT_ID,
  source: "default",
  locale: "id",
  timezone: "Asia/Jakarta",
  currency: "IDR",
  terminology_overrides: {},
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): LocalizationQueryRpcClient & { calls: number } {
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

describe("resolveLocaleContext", () => {
  test("parses a tenant-source row (array response, matching Supabase's table-returning RPC shape)", async () => {
    const client = fakeClient({ data: [TENANT_SOURCE_ROW], error: null });
    const context = await resolveLocaleContext(client, { tenantId: TENANT_ID });
    assert.equal(context.source, "tenant");
    assert.equal(context.locale, "en");
  });

  test("parses the platform-default fallback", async () => {
    const client = fakeClient({ data: [DEFAULT_SOURCE_ROW], error: null });
    const context = await resolveLocaleContext(client, { tenantId: TENANT_ID });
    assert.equal(context.source, "default");
    assert.equal(context.locale, "id");
    assert.equal(context.currency, "IDR");
  });

  test("passes a null userAuthUserId by default", async () => {
    const client = fakeClient({ data: [DEFAULT_SOURCE_ROW], error: null }) as LocalizationQueryRpcClient & { calls: number };
    let capturedArgs: Record<string, unknown> | undefined;
    client.rpc = async (_fn, args) => {
      capturedArgs = args;
      return { data: [DEFAULT_SOURCE_ROW], error: null };
    };
    await resolveLocaleContext(client, { tenantId: TENANT_ID });
    assert.equal(capturedArgs?.["p_user_auth_user_id"], null);
  });

  test("wraps a database error into a typed LocalizationQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(
      () => resolveLocaleContext(client, { tenantId: TENANT_ID }),
      (err: unknown) => {
        assert.ok(err instanceof LocalizationQueryError);
        return true;
      },
    );
  });
});

describe("LocaleContextCache", () => {
  test("serves a cached context within the TTL without a second RPC call", async () => {
    const client = fakeClient({ data: [TENANT_SOURCE_ROW], error: null });
    const cache = new LocaleContextCache(60_000);
    const now = 1_000_000;

    await resolveLocaleContext(client, { tenantId: TENANT_ID }, cache, now);
    await resolveLocaleContext(client, { tenantId: TENANT_ID }, cache, now + 1_000);

    assert.equal(client.calls, 1);
  });

  test("keys the cache independently per user (a user override must not leak to another user's lookup)", async () => {
    const client = fakeClient({ data: [TENANT_SOURCE_ROW], error: null });
    const cache = new LocaleContextCache(60_000);
    const now = 1_000_000;

    await resolveLocaleContext(client, { tenantId: TENANT_ID, userAuthUserId: USER_ID }, cache, now);
    await resolveLocaleContext(client, { tenantId: TENANT_ID, userAuthUserId: null }, cache, now + 1_000);

    assert.equal(client.calls, 2);
  });

  test("invalidate(tenantId) drops every cached entry for that tenant, regardless of user key", async () => {
    const client = fakeClient({ data: [TENANT_SOURCE_ROW], error: null });
    const cache = new LocaleContextCache(60_000);
    const now = 1_000_000;

    await resolveLocaleContext(client, { tenantId: TENANT_ID, userAuthUserId: USER_ID }, cache, now);
    await resolveLocaleContext(client, { tenantId: TENANT_ID, userAuthUserId: null }, cache, now);
    cache.invalidate(TENANT_ID);
    await resolveLocaleContext(client, { tenantId: TENANT_ID, userAuthUserId: USER_ID }, cache, now + 1_000);

    assert.equal(client.calls, 3);
  });
});
