import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { buildSessionCookieOptions, DEFAULT_SESSION_MAX_AGE_SECONDS } from "./session-cookie-options.ts";

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
