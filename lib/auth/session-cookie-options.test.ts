import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { buildSessionCookieOptions, mergeSessionCookieOptions, DEFAULT_SESSION_MAX_AGE_SECONDS } from "./session-cookie-options.ts";

describe("buildSessionCookieOptions", () => {
  test("is always httpOnly, sameSite=lax, path=/", () => {
    const options = buildSessionCookieOptions({ isProduction: true });
    assert.equal(options.httpOnly, true);
    assert.equal(options.sameSite, "lax");
    assert.equal(options.path, "/");
  });

  test("secure=true in production", () => {
    assert.equal(buildSessionCookieOptions({ isProduction: true }).secure, true);
  });

  test("secure=false outside production (so local HTTP development still works)", () => {
    assert.equal(buildSessionCookieOptions({ isProduction: false }).secure, false);
  });

  test("defaults maxAge to the documented 7-day value", () => {
    assert.equal(buildSessionCookieOptions({ isProduction: true }).maxAge, DEFAULT_SESSION_MAX_AGE_SECONDS);
    assert.equal(DEFAULT_SESSION_MAX_AGE_SECONDS, 604800);
  });

  test("accepts a caller-supplied maxAge override", () => {
    assert.equal(buildSessionCookieOptions({ isProduction: true, maxAgeSeconds: 3600 }).maxAge, 3600);
  });
});

// CG-AUDIT-2026-09-02 D3c: these assert the actual composition lib/supabase/server.ts runs
// (session cookie options merged against @supabase/ssr's own per-call options), not just the
// pure builder's own return value in isolation -- the gap the audit's own finding named
// explicitly ("the existing unit test asserts only the pure options-builder function's
// return value, never the actual composition that runs in server.ts").
describe("mergeSessionCookieOptions", () => {
  const appOptions = buildSessionCookieOptions({ isProduction: true });

  test("the app's httpOnly/secure/sameSite/path always win over @supabase/ssr's own insecure defaults for a real session-set call", () => {
    // Shape @supabase/ssr@0.12.3's own DEFAULT_COOKIE_OPTIONS + applyServerStorage produce for
    // a genuine session write: httpOnly:false, a 400-day maxAge, forced every time.
    const libraryOptions = { path: "/", sameSite: "lax", httpOnly: false, maxAge: 400 * 24 * 60 * 60 };
    const merged = mergeSessionCookieOptions(appOptions, libraryOptions);
    assert.equal(merged.httpOnly, true, "must never be readable from client-side JavaScript");
    assert.equal(merged.secure, true);
    assert.equal(merged.sameSite, "lax");
    assert.equal(merged.path, "/");
    assert.equal(merged.maxAge, DEFAULT_SESSION_MAX_AGE_SECONDS, "must use the app's 7-day policy, never the library's 400-day default");
  });

  test("a genuine cookie-clear (logout, or stale-chunk cleanup) still expires the cookie -- maxAge:0 passes through", () => {
    const libraryClearOptions = { path: "/", sameSite: "lax", httpOnly: false, maxAge: 0 };
    const merged = mergeSessionCookieOptions(appOptions, libraryClearOptions);
    assert.equal(merged.maxAge, 0, "overriding maxAge:0 back to a 7-day value would silently break logout");
    assert.equal(merged.httpOnly, true);
    assert.equal(merged.secure, true);
  });

  test("an incidental field the library sets (e.g. domain) passes through untouched", () => {
    const libraryOptions = { path: "/", sameSite: "lax", httpOnly: false, maxAge: 400 * 24 * 60 * 60, domain: ".example.test" };
    const merged = mergeSessionCookieOptions(appOptions, libraryOptions);
    assert.equal(merged.domain, ".example.test");
  });
});
