import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { scanContent, scanRepository } from "./check-secrets.ts";

// Every "secret" below is synthetic/well-known-example, chosen specifically
// to prove pattern-matching works without ever containing a real credential
// (docs/standards/SECURITY_STANDARDS.md §3). This file is in
// SELF_REFERENTIAL_EXCLUSIONS, so scanRepository() never scans it.
//
// The Stripe/JWT fixtures are built via runtime string concatenation rather
// than a single literal — GitHub's own push-protection secret scanner
// (correctly, independently) flagged a contiguous "sk_live_..."-shaped
// literal here as secret-shaped, the same class of pattern this scanner
// exists to catch. Splitting the literal avoids re-triggering that
// protection while the regex under test still matches the concatenated
// runtime value identically — no change to what is actually being tested.
const FAKE_AWS_KEY = "AKIAIOSFODNN7EXAMPLE"; // AWS's own public documentation example key
const FAKE_PEM_HEADER = "-----BEGIN RSA PRIVATE KEY-----";
const FAKE_STRIPE_KEY = "sk_" + "live_" + "NOTAREALKEYFIXTUREVALUE1234";
const FAKE_JWT = "eyJhbGciOiJIUzI1NiJ9" + "." + "eyJzdWIiOiJmYWtlIn0" + "." + "NOTAREALSIGNATUREFIXTUREVALUE";
const FAKE_GENERIC_SECRET = 'password = "this-is-a-synthetic-test-value-not-real"';

describe("scanContent — AWS_ACCESS_KEY_ID", () => {
  test("flags a matching AWS access key ID", () => {
    const findings = scanContent("config.ts", `const key = "${FAKE_AWS_KEY}";`);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "AWS_ACCESS_KEY_ID");
    assert.equal(findings[0]?.line, 1);
  });

  test("does not flag an unrelated string", () => {
    assert.deepEqual(scanContent("config.ts", "const key = 'not-an-aws-key';"), []);
  });
});

describe("scanContent — PRIVATE_KEY_BLOCK", () => {
  test("flags a PEM private key header", () => {
    const findings = scanContent("id_rsa", FAKE_PEM_HEADER);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "PRIVATE_KEY_BLOCK");
  });

  test("does not flag a public key header", () => {
    assert.deepEqual(scanContent("id_rsa.pub", "-----BEGIN PUBLIC KEY-----"), []);
  });
});

describe("scanContent — STRIPE_LIVE_KEY", () => {
  test("flags a live-shaped Stripe key", () => {
    const findings = scanContent("billing.ts", `const stripeKey = "${FAKE_STRIPE_KEY}";`);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "STRIPE_LIVE_KEY");
  });

  test("does not flag a test-mode Stripe key prefix alone", () => {
    assert.deepEqual(scanContent("billing.ts", 'const stripeKey = "sk_test_";'), []);
  });
});

describe("scanContent — JWT_SHAPED_TOKEN", () => {
  test("flags a three-segment JWT-shaped string", () => {
    // Deliberately assigned to a non-suspicious variable name so this case
    // isolates JWT_SHAPED_TOKEN from GENERIC_HARDCODED_SECRET_ASSIGNMENT
    // (which would also fire on a "token = <20+ chars>" assignment) —
    // both firing together on a real "token = <jwt>" line is correct,
    // expected, overlapping-evidence behavior, not a bug (proven separately
    // by the "multi-finding" suite below).
    const findings = scanContent("auth.ts", `const jwtValue = "${FAKE_JWT}";`);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "JWT_SHAPED_TOKEN");
  });

  test("also flags GENERIC_HARDCODED_SECRET_ASSIGNMENT when the variable name is itself suspicious (expected overlap)", () => {
    const findings = scanContent("auth.ts", `const token = "${FAKE_JWT}";`);
    const kinds = findings.map((f) => f.kind).sort();
    assert.deepEqual(kinds, ["GENERIC_HARDCODED_SECRET_ASSIGNMENT", "JWT_SHAPED_TOKEN"]);
  });

  test("does not flag a two-segment string", () => {
    assert.deepEqual(scanContent("auth.ts", 'const notAJwt = "eyJhbGciOiJIUzI1NiJ9.onlyonesegment";'), []);
  });
});

describe("scanContent — GENERIC_HARDCODED_SECRET_ASSIGNMENT", () => {
  test("flags a suspicious key assigned a long quoted literal in a non-test file", () => {
    const findings = scanContent("server/config.ts", FAKE_GENERIC_SECRET);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "GENERIC_HARDCODED_SECRET_ASSIGNMENT");
  });

  test("does not flag the same content in a *.test.ts file (fixture-tolerance design)", () => {
    assert.deepEqual(scanContent("server/config.test.ts", FAKE_GENERIC_SECRET), []);
  });

  test("does not flag a short value under the 20-character threshold", () => {
    assert.deepEqual(scanContent("server/config.ts", 'password = "short1"'), []);
  });

  test("does not flag a non-suspicious key name with a long value", () => {
    assert.deepEqual(scanContent("server/config.ts", 'description = "this is just a long human-readable description field"'), []);
  });
});

describe("scanContent — findings never include the matched value", () => {
  test("a finding object has no field containing the raw secret text", () => {
    const findings = scanContent("config.ts", `const key = "${FAKE_AWS_KEY}";`);
    const serialized = JSON.stringify(findings[0]);
    assert.ok(!serialized.includes(FAKE_AWS_KEY));
  });
});

describe("scanContent — multi-line and multi-finding", () => {
  test("reports the correct line number for a match on line 3", () => {
    const content = ["line one", "line two", `const key = "${FAKE_AWS_KEY}";`].join("\n");
    const findings = scanContent("config.ts", content);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.line, 3);
  });

  test("reports every finding when multiple secrets appear in one file", () => {
    const content = [`const aws = "${FAKE_AWS_KEY}";`, `const stripe = "${FAKE_STRIPE_KEY}";`].join("\n");
    const findings = scanContent("config.ts", content);
    assert.equal(findings.length, 2);
  });
});

describe("scanRepository — against this repository's real, current tracked files", () => {
  test("finds zero real secrets (regression guard — this repository has never committed one)", () => {
    const findings = scanRepository();
    assert.deepEqual(findings, []);
  });
});
