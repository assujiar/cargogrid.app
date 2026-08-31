import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { selectClientIp, resolveRequestClientIp, CLIENT_IP_HEADERS } from "./client-ip.ts";

describe("selectClientIp", () => {
  test("prefers x-real-ip, the header a client cannot forge past the proxy", () => {
    assert.equal(selectClientIp("203.0.113.9", "198.51.100.1"), "203.0.113.9");
  });

  test("THE SPOOFING CASE: takes the LAST x-forwarded-for hop, never the first", () => {
    // A browser that sends `x-forwarded-for: 10.0.0.1` gets the proxy's observation appended
    // after it. Reading the first entry -- the conventional idiom -- would hand an attacker
    // membership of any allowlist for the price of one header.
    assert.equal(selectClientIp(null, "10.0.0.1, 203.0.113.9"), "203.0.113.9");
  });

  test("a single-hop x-forwarded-for is used as-is", () => {
    assert.equal(selectClientIp(null, "203.0.113.9"), "203.0.113.9");
  });

  test("whitespace around hops is trimmed", () => {
    assert.equal(selectClientIp(null, "  10.0.0.1 ,   203.0.113.9  "), "203.0.113.9");
  });

  test("an empty or whitespace-only x-real-ip falls through rather than winning", () => {
    assert.equal(selectClientIp("   ", "203.0.113.9"), "203.0.113.9");
    assert.equal(selectClientIp("", "203.0.113.9"), "203.0.113.9");
  });

  test("no headers at all is null, not a fabricated address", () => {
    assert.equal(selectClientIp(null, null), null);
    assert.equal(selectClientIp(undefined, undefined), null);
    assert.equal(selectClientIp(null, ""), null);
    assert.equal(selectClientIp(null, " , , "), null);
  });

  test("IPv6 survives intact -- the allowlist accepts IPv6 CIDRs", () => {
    assert.equal(selectClientIp("2001:db8::1", null), "2001:db8::1");
    assert.equal(selectClientIp(null, "10.0.0.1, 2001:db8::1"), "2001:db8::1");
  });

  test("the trusted-header order is stated once and asserted here", () => {
    assert.deepEqual([...CLIENT_IP_HEADERS], ["x-real-ip", "x-forwarded-for"]);
  });
});

describe("resolveRequestClientIp", () => {
  test("returns null outside a request instead of throwing", async () => {
    // This test itself runs with no Next.js request in scope, which is precisely the
    // condition a background job or scheduled sweep is in. Returning null means those callers
    // skip the address check, exactly as they did before the control existed -- a throw here
    // would break every mutation the suite exercises.
    assert.equal(await resolveRequestClientIp(), null);
  });
});
