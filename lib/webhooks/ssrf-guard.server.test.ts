import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { checkWebhookDispatchUrlIsSafe, isPrivateOrReservedIpv4, isPrivateOrReservedIpv6 } from "./ssrf-guard.server.ts";

describe("isPrivateOrReservedIpv4", () => {
  test("flags loopback, RFC1918, link-local/cloud-metadata, and CGNAT ranges", () => {
    assert.equal(isPrivateOrReservedIpv4("127.0.0.1"), true);
    assert.equal(isPrivateOrReservedIpv4("10.1.2.3"), true);
    assert.equal(isPrivateOrReservedIpv4("172.16.0.1"), true);
    assert.equal(isPrivateOrReservedIpv4("172.31.255.255"), true);
    assert.equal(isPrivateOrReservedIpv4("192.168.1.1"), true);
    assert.equal(isPrivateOrReservedIpv4("169.254.169.254"), true); // cloud metadata
    assert.equal(isPrivateOrReservedIpv4("100.64.0.1"), true);
    assert.equal(isPrivateOrReservedIpv4("0.0.0.0"), true);
  });

  test("does not flag ordinary public addresses", () => {
    assert.equal(isPrivateOrReservedIpv4("8.8.8.8"), false);
    assert.equal(isPrivateOrReservedIpv4("172.15.255.255"), false); // just below 172.16.0.0/12
    assert.equal(isPrivateOrReservedIpv4("172.32.0.0"), false); // just above
  });
});

describe("isPrivateOrReservedIpv6", () => {
  test("flags loopback, link-local, and unique-local ranges, plus an IPv4-mapped private address", () => {
    assert.equal(isPrivateOrReservedIpv6("::1"), true);
    assert.equal(isPrivateOrReservedIpv6("fe80::1"), true);
    assert.equal(isPrivateOrReservedIpv6("fd00::1"), true);
    assert.equal(isPrivateOrReservedIpv6("::ffff:127.0.0.1"), true);
  });

  test("does not flag an ordinary public IPv6 address", () => {
    assert.equal(isPrivateOrReservedIpv6("2001:4860:4860::8888"), false);
  });
});

describe("checkWebhookDispatchUrlIsSafe", () => {
  test("rejects a non-https scheme before ever resolving DNS", async () => {
    const result = await checkWebhookDispatchUrlIsSafe("http://example.test/webhook", async () => {
      throw new Error("must not resolve DNS for a rejected scheme");
    });
    assert.equal(result.safe, false);
    assert.match(result.reason ?? "", /https/);
  });

  test("rejects an unparseable URL", async () => {
    const result = await checkWebhookDispatchUrlIsSafe("not a url");
    assert.equal(result.safe, false);
  });

  test("rejects a literal private IPv4 host without any DNS lookup", async () => {
    const result = await checkWebhookDispatchUrlIsSafe("https://169.254.169.254/latest/meta-data/", async () => {
      throw new Error("must not resolve DNS for a literal IP host");
    });
    assert.equal(result.safe, false);
    assert.match(result.reason ?? "", /private\/reserved/);
  });

  test("accepts a literal public IPv4 host without any DNS lookup", async () => {
    const result = await checkWebhookDispatchUrlIsSafe("https://93.184.216.34/webhook", async () => {
      throw new Error("must not resolve DNS for a literal IP host");
    });
    assert.equal(result.safe, true);
  });

  test("DNS-rebinding case: a hostname that resolves to the cloud metadata address is refused, exactly the gap PLT-129's own registration-time check could not close", async () => {
    const result = await checkWebhookDispatchUrlIsSafe("https://n8n-rebind.example.test/webhook", async () => [{ address: "169.254.169.254", family: 4 }]);
    assert.equal(result.safe, false);
    assert.match(result.reason ?? "", /169\.254\.169\.254/);
  });

  test("a hostname with a mixed answer set (one public, one private) is refused -- a single unsafe address is enough", async () => {
    const result = await checkWebhookDispatchUrlIsSafe("https://mixed.example.test/webhook", async () => [
      { address: "8.8.8.8", family: 4 },
      { address: "10.0.0.5", family: 4 },
    ]);
    assert.equal(result.safe, false);
  });

  test("a hostname resolving only to public addresses is accepted", async () => {
    const result = await checkWebhookDispatchUrlIsSafe("https://public.example.test/webhook", async () => [{ address: "203.0.113.10", family: 4 }]);
    assert.equal(result.safe, true);
  });

  test("a DNS resolution failure is treated as unsafe, never as a silent pass", async () => {
    const result = await checkWebhookDispatchUrlIsSafe("https://nxdomain.example.test/webhook", async () => {
      throw new Error("ENOTFOUND");
    });
    assert.equal(result.safe, false);
    assert.match(result.reason ?? "", /DNS resolution failed/);
  });

  test("an empty answer set is treated as unsafe", async () => {
    const result = await checkWebhookDispatchUrlIsSafe("https://empty.example.test/webhook", async () => []);
    assert.equal(result.safe, false);
  });
});
