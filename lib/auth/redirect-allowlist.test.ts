import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { validateRedirectTarget } from "./redirect-allowlist.ts";

describe("validateRedirectTarget", () => {
  test("accepts a same-origin relative path", () => {
    assert.equal(validateRedirectTarget("/dashboard").safe, true);
    assert.equal(validateRedirectTarget("/tenant/acme/admin?tab=users").safe, true);
  });

  test("rejects an empty or whitespace-only target", () => {
    assert.equal(validateRedirectTarget("").safe, false);
    assert.equal(validateRedirectTarget("   ").safe, false);
    assert.equal(validateRedirectTarget("").reason, "empty_target");
  });

  test("rejects a protocol-relative target (the classic //evil.com open-redirect bypass)", () => {
    const result = validateRedirectTarget("//evil.example");
    assert.equal(result.safe, false);
    assert.equal(result.reason, "dangerous_prefix");
  });

  test("rejects a backslash-prefixed target (a second open-redirect bypass some parsers accept)", () => {
    assert.equal(validateRedirectTarget("/\\evil.example").safe, false);
    assert.equal(validateRedirectTarget("\\evil.example").safe, false);
  });

  test("rejects a javascript:/data:/vbscript: scheme", () => {
    assert.equal(validateRedirectTarget("javascript:alert(1)").safe, false);
    assert.equal(validateRedirectTarget("data:text/html,<script>alert(1)</script>").safe, false);
    assert.equal(validateRedirectTarget("vbscript:msgbox(1)").safe, false);
  });

  test("is case-insensitive when matching dangerous prefixes", () => {
    assert.equal(validateRedirectTarget("JavaScript:alert(1)").safe, false);
  });

  test("rejects an absolute URL to a non-allowlisted origin", () => {
    const result = validateRedirectTarget("https://evil.example/phish", ["https://cargogrid.app"]);
    assert.equal(result.safe, false);
    assert.equal(result.reason, "origin_not_allowlisted");
  });

  test("accepts an absolute URL whose origin is explicitly allowlisted", () => {
    const result = validateRedirectTarget("https://cargogrid.app/dashboard", ["https://cargogrid.app"]);
    assert.equal(result.safe, true);
  });

  test("rejects a string that is neither a relative path nor a parseable absolute URL", () => {
    const result = validateRedirectTarget("not a url at all");
    assert.equal(result.safe, false);
    assert.equal(result.reason, "not_a_relative_path_or_valid_url");
  });
});
