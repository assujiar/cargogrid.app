/**
 * Tests for scripts/env/validate.ts — Prompt 86 §28: "Schema/cross-field/
 * environment-class validation and redaction tests. Secret-in-client,
 * missing required, malformed URL, production-link and deprecated variable
 * negatives."
 *
 * Uses Node's built-in test runner (`node:test`) — no test framework is
 * chosen yet (that ADR is `PH0-091`'s job, `ADR-CAND-ARCH-022`). `node:test`
 * is a zero-dependency, real, functioning choice for this Phase 0 checkpoint
 * only; when `PH0-091` formalizes the project-wide framework, this file
 * should be migrated (or kept, if `node:test` is what's chosen) — that
 * decision is explicitly out of scope here, see `docs/build-log/phase-00/PH0-86.md` section 8.
 *
 * Run: `pnpm test`
 */

import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { loadEnv, EnvValidationError, summarizeForAudit, fingerprintAll } from "./validate.ts";

const VALID_LOCAL_ENV = {
  CARGOGRID_ENV: "local",
  NODE_ENV: "development",
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
  NEXT_PUBLIC_SUPABASE_ANON_KEY: "test-anon-key",
  SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key",
  NEXT_PUBLIC_SITE_URL: "http://127.0.0.1:3000",
};

const VALID_PRODUCTION_ENV = {
  CARGOGRID_ENV: "production",
  NODE_ENV: "production",
  NEXT_PUBLIC_SUPABASE_URL: "https://cargogrid-prod.supabase.co",
  NEXT_PUBLIC_SUPABASE_ANON_KEY: "prod-anon-key",
  SUPABASE_SERVICE_ROLE_KEY: "prod-service-role-key",
  NEXT_PUBLIC_SITE_URL: "https://app.cargogrid.example",
};

describe("loadEnv — positive cases", () => {
  test("accepts a fully valid local environment", () => {
    const env = loadEnv(VALID_LOCAL_ENV);
    assert.equal(env.environmentClass, "local");
    assert.equal(env.values.NEXT_PUBLIC_SUPABASE_URL, "http://127.0.0.1:54321");
  });

  test("accepts a fully valid production environment (non-loopback)", () => {
    const env = loadEnv(VALID_PRODUCTION_ENV);
    assert.equal(env.environmentClass, "production");
  });

  test("evidence-readback: fingerprints prove real values were loaded without exposing them", () => {
    const env = loadEnv(VALID_LOCAL_ENV);
    const fp = fingerprintAll(env);
    assert.ok(fp.SUPABASE_SERVICE_ROLE_KEY);
    assert.ok(!fp.SUPABASE_SERVICE_ROLE_KEY.includes("test-service-role-key"));
  });

  test("audit summary never contains raw values", () => {
    const env = loadEnv(VALID_LOCAL_ENV);
    const summary = summarizeForAudit(env).join("\n");
    assert.ok(!summary.includes("test-service-role-key"));
    assert.ok(!summary.includes("test-anon-key"));
    assert.ok(summary.includes("SET"));
  });
});

describe("loadEnv — negative cases", () => {
  test("rejects missing CARGOGRID_ENV", () => {
    const { CARGOGRID_ENV, ...rest } = VALID_LOCAL_ENV;
    assert.throws(() => loadEnv(rest), EnvValidationError);
  });

  test("rejects an invalid CARGOGRID_ENV value", () => {
    assert.throws(() => loadEnv({ ...VALID_LOCAL_ENV, CARGOGRID_ENV: "not-a-real-tier" }), EnvValidationError);
  });

  test("rejects missing required variable(s), and names them without leaking values", () => {
    const { SUPABASE_SERVICE_ROLE_KEY, ...rest } = VALID_LOCAL_ENV;
    try {
      loadEnv(rest);
      assert.fail("expected EnvValidationError");
    } catch (error) {
      assert.ok(error instanceof EnvValidationError);
      assert.ok(error.message.includes("SUPABASE_SERVICE_ROLE_KEY"));
      assert.ok(!error.message.includes(SUPABASE_SERVICE_ROLE_KEY));
    }
  });

  test("rejects a malformed URL and withholds the value in the error", () => {
    const secretLookingUrl = "not-a-url-super-secret-marker-zzz";
    try {
      loadEnv({ ...VALID_LOCAL_ENV, NEXT_PUBLIC_SUPABASE_URL: secretLookingUrl });
      assert.fail("expected EnvValidationError");
    } catch (error) {
      assert.ok(error instanceof EnvValidationError);
      assert.ok(error.message.includes("NEXT_PUBLIC_SUPABASE_URL"));
      assert.ok(!error.message.includes(secretLookingUrl));
    }
  });

  test("production-link safeguard: local env class rejects a non-loopback Supabase URL", () => {
    assert.throws(
      () =>
        loadEnv({
          ...VALID_LOCAL_ENV,
          NEXT_PUBLIC_SUPABASE_URL: "https://someone-elses-real-project.supabase.co",
        }),
      EnvValidationError,
    );
  });

  test("production-link safeguard (reverse direction): production env class rejects a loopback Supabase URL", () => {
    assert.throws(
      () =>
        loadEnv({
          ...VALID_PRODUCTION_ENV,
          NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
        }),
      EnvValidationError,
    );
  });

  test("empty string is treated as missing, not a valid empty value", () => {
    assert.throws(() => loadEnv({ ...VALID_LOCAL_ENV, NEXT_PUBLIC_SUPABASE_ANON_KEY: "" }), EnvValidationError);
  });
});
