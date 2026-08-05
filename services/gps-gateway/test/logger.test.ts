import { test } from "node:test";
import assert from "node:assert/strict";
import { log, type LogFields } from "../src/logger.ts";

// ATW-246 finding 7 (log redaction bypass): `log()` writes to console.log/console.error
// depending on level -- temporarily intercept both (never dependent on knowing in advance
// which one a given call will use) and restore them afterward, regardless of assertion
// outcome.
function captureLog(level: "info" | "warn" | "error", message: string, fields?: LogFields): Record<string, unknown> {
  let captured: string | undefined;
  const sink = (line: string) => {
    captured = line;
  };
  const originalLog = console.log;
  const originalError = console.error;
  console.log = sink;
  console.error = sink;
  try {
    log(level, message, fields);
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }
  if (captured === undefined) {
    throw new Error("expected log() to write exactly one line");
  }
  return JSON.parse(captured) as Record<string, unknown>;
}

test("pre-existing behavior unchanged: a sensitive-named field (key match) is still fully redacted regardless of its value's own shape", () => {
  const parsed = captureLog("info", "device connected", { apiKey: "not-even-credential-shaped" });
  assert.equal(parsed.apiKey, "[REDACTED]");
});

test("pre-existing behavior unchanged: a normal, short, non-sensitive message and fields pass through completely unchanged", () => {
  const parsed = captureLog("info", "gps-gateway started", { tcpPort: 6060, tcpHost: "0.0.0.0" });
  assert.equal(parsed.message, "gps-gateway started");
  assert.equal(parsed.tcpPort, 6060);
  assert.equal(parsed.tcpHost, "0.0.0.0");
  assert.equal(parsed.level, "info");
  assert.equal(typeof parsed.timestamp, "string");
});

// ATW-246 finding 7: the dominant real logging pathway (server.ts) routes dynamic/
// error-derived content through the free-text `message` string, which the original
// redactFields() never scanned at all -- only the optional `fields` object's own keys.
test("ATW-246 finding 7: a JWT-shaped token embedded in the free-text MESSAGE (not fields) is now redacted", () => {
  // Built via concatenation, not a single literal (see the identical rationale on the
  // Stripe-shaped fixture below) -- only needs to match logger.ts's own JWT_SHAPED_TOKEN
  // regex shape, not resemble a contiguous token to source scanners.
  const fakeJwt =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
    "eyJzdWIiOiIxMjM0NTY3ODkwIn0." +
    "dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U";
  const parsed = captureLog("error", `handshake_authentication_failed: token ${fakeJwt} rejected`);
  const message = String(parsed.message);
  assert.ok(!message.includes(fakeJwt), "expected the JWT-shaped token embedded in message to be redacted, not logged verbatim");
  assert.ok(message.includes("[REDACTED]"), "expected a redaction marker in place of the JWT-shaped token");
});

test("ATW-246 finding 7: an AWS-access-key-shaped value embedded in message is redacted", () => {
  // Built via concatenation, not a single literal -- see the identical rationale above.
  const awsShapedFixture = "AKIA" + "ABCDEFGHIJKLMNOP";
  const parsed = captureLog("error", `unexpected value ${awsShapedFixture} found in payload`);
  const message = String(parsed.message);
  assert.ok(!message.includes(awsShapedFixture));
  assert.ok(message.includes("[REDACTED]"));
});

test("ATW-246 finding 7: a generic secret-shaped key=value assignment embedded in message is redacted (mirrors scripts/security/check-secrets.ts's own GENERIC_HARDCODED_SECRET_ASSIGNMENT shape)", () => {
  // The exact scenario the probe flagged: codec8e.ts's own thrown-error message embeds
  // unbounded, attacker-controlled payload content (JSON.stringify(imei)) verbatim --
  // simulated here as a malformed-handshake message carrying a credential-shaped value.
  const parsed = captureLog("error", 'malformed_imei_handshake: expected an all-digit IMEI, got "token=abcdefghijklmnopqrstuvwxyz123456"');
  const message = String(parsed.message);
  assert.ok(!message.includes("abcdefghijklmnopqrstuvwxyz123456"), "expected the credential-shaped substring to be redacted");
});

test("ATW-246 finding 7: a credential-shaped VALUE under a non-sensitive-looking field key is also redacted (value-content scan, not just fields' own key-name scan)", () => {
  // Built via concatenation, not a single literal, so this synthetic fixture (which only
  // needs to match logger.ts's own STRIPE_LIVE_KEY shape, /\bsk_live_[0-9a-zA-Z]{16,}\b/,
  // not a real credential) does not itself resemble a contiguous secret to source scanners.
  const stripeShapedFixture = "sk_" + "live_" + "ABCDEFGHIJKLMNOPQRSTUVWX";
  const parsed = captureLog("error", "provider callback", { rawBody: stripeShapedFixture });
  assert.equal(parsed.rawBody, "[REDACTED]");
});

// ATW-246 finding 7: unbounded attacker payload reaching logs.
test("ATW-246 finding 7: an oversized attacker-controlled value embedded in message is truncated to a bounded length", () => {
  const hugePayload = "A".repeat(10_000);
  const parsed = captureLog("error", `malformed_imei_handshake: expected an all-digit IMEI, got "${hugePayload}"`);
  const message = String(parsed.message);
  assert.ok(message.length < 3_000, `expected the logged message to be bounded well under the original ~10,000-char payload, got length ${message.length}`);
  assert.ok(message.includes("truncated"), "expected a truncation marker on an oversized message");
});

test("ATW-246 finding 7: a short message well under the truncation bound is never marked truncated", () => {
  const parsed = captureLog("info", "connection closed: oversized_packet");
  assert.equal(parsed.message, "connection closed: oversized_packet");
});
