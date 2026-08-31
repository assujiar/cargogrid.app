import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import { resolveSupremeAdminAccess, type SupremeAdminGuardDeps } from "./supreme-admin-guard.ts";

/**
 * ISS-2026-160's remaining half, settled empirically rather than by reading a library.
 *
 * That entry's CI-wiring symptoms were fixed at HDN-380, but it stayed open on a product
 * question it phrased sharply: several e2e specs are named for failing safe "when the backend
 * itself is unreachable", and the entry said that either the guard genuinely degrades to a
 * redirect, "or those spec names describe an intent the implementation never had. That must be
 * decided, not papered over."
 *
 * It does. These tests prove it against a real, unroutable address -- 127.0.0.1:1, where the
 * connection is refused immediately, needs no external network, and works behind a proxy -- so
 * the claim rests on what the client actually does rather than on what its documentation says.
 * Mocking the failure would prove only that the mock was written correctly.
 *
 * WHAT FAILING SAFE MEANS HERE, AND WHAT IT DELIBERATELY DOES NOT COVER
 *
 *   Under uncertainty the guard must DENY, and denying is a redirect to /login rather than a
 *   crash. That is what these tests pin.
 *
 *   The separate case of a deployment with no NEXT_PUBLIC_SUPABASE_URL configured at all still
 *   throws during client construction, before any guard logic runs -- and that is deliberate,
 *   not an unfixed remnant. An unconfigured deployment is an operator error, and turning it into
 *   a silent redirect would make a misconfigured production look exactly like "every user is
 *   logged out", which is far harder to diagnose than a loud failure at startup. Failing safe is
 *   about denying access when the answer is unknown; it is not about hiding a broken deployment.
 */

const UNROUTABLE = "http://127.0.0.1:1";
const PLACEHOLDER_KEY = "unreachable-backend-test-placeholder";
/**
 * Any non-empty token forces `getUser` to make the real network call to /auth/v1/user -- the
 * path a request WITH a session cookie takes -- because the client sends it as a bearer token
 * and never parses it locally (verified directly: this exact string produces the same
 * AuthRetryableFetchError a JWT-shaped one does).
 *
 * Deliberately NOT JWT-shaped. A JWT-shaped literal here is correctly flagged by
 * `scripts/security/check-secrets.ts`, and the right response to a secret scanner finding a
 * fake secret is to stop writing fake secrets, not to teach the scanner to ignore a shape.
 */
const PROBE_TOKEN = "unreachable-backend-probe-token";

describe("guard fail-safe against an unreachable Supabase backend (ISS-2026-160)", () => {
  test("auth.getUser() resolves with an error instead of throwing", async () => {
    const client = createClient(UNROUTABLE, PLACEHOLDER_KEY);
    // No try/catch: if this ever starts throwing, the test fails here, which is the point.
    // A throw would escape the guard entirely and surface as a 500.
    const result = await client.auth.getUser(PROBE_TOKEN);
    assert.equal(result.data.user, null);
    assert.ok(result.error, "an unreachable backend must produce an error result, not a user");
  });

  test("rpc() resolves with an error instead of throwing", async () => {
    const client = createClient(UNROUTABLE, PLACEHOLDER_KEY);
    const result = await client.rpc("resolve_access_context", { p_auth_user_id: "00000000-0000-0000-0000-000000000000" });
    assert.equal(result.data, null);
    assert.ok(result.error, "an unreachable backend must produce an error result, not a context");
  });

  test("the composed guard returns unauthenticated -- a redirect to /login, never a crash", async () => {
    const client = createClient(UNROUTABLE, PLACEHOLDER_KEY);

    // The real wiring from lib/portal/*-guard-deps.server.ts, reproduced here against a real
    // client. Every one of this repository's ten guard-deps modules maps an error to null the
    // same way (four distinct wirings; the other six delegate to buildTenantAdminGuardDeps),
    // so pinning one pins the shape they all share.
    const deps: SupremeAdminGuardDeps = {
      async getCurrentUserId() {
        const { data, error } = await client.auth.getUser(PROBE_TOKEN);
        if (error || !data.user) return null;
        return data.user.id;
      },
      async resolveGlobalAccessContext(authUserId: string) {
        const { data, error } = await client.rpc("resolve_access_context", { p_auth_user_id: authUserId });
        if (error || !data) return null;
        return { layer: (data as { layer: string }).layer };
      },
    };

    const result = await resolveSupremeAdminAccess(deps);
    // "unauthenticated" is what every portal page turns into redirect("/login").
    assert.equal(result.status, "unauthenticated");
  });

  test("an unreachable backend never yields 'allowed' -- the property that actually matters", async () => {
    const client = createClient(UNROUTABLE, PLACEHOLDER_KEY);

    // The adversarial case: the identity check somehow succeeds and only the authority lookup
    // is unreachable. Failing safe means the missing answer denies rather than defaults.
    const deps: SupremeAdminGuardDeps = {
      async getCurrentUserId() {
        return "11111111-1111-1111-1111-111111111111";
      },
      async resolveGlobalAccessContext(authUserId: string) {
        const { data, error } = await client.rpc("resolve_access_context", { p_auth_user_id: authUserId });
        if (error || !data) return null;
        return { layer: (data as { layer: string }).layer };
      },
    };

    const result = await resolveSupremeAdminAccess(deps);
    assert.notEqual(result.status, "allowed");
    assert.equal(result.status, "forbidden");
    if (result.status === "forbidden") {
      // "none", not a fabricated layer -- an unknown authority is reported as absent.
      assert.equal(result.layer, "none");
    }
  });
});
