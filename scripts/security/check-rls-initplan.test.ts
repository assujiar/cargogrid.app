import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  blankLineComments,
  parseFunctionSignatures,
  parsePolicyStatements,
  findBareAuthCalls,
  findHelperCallSites,
  scanRepository,
} from "./check-rls-initplan.ts";

describe("blankLineComments", () => {
  test("blanks a -- comment but preserves line/column positions", () => {
    const input = "select 1; -- create policy p on t;\nselect 2;";
    const blanked = blankLineComments(input);
    assert.equal(blanked.length, input.length);
    assert.ok(!blanked.includes("create policy"));
    assert.ok(blanked.includes("select 2;"));
  });

  test("does not blank a literal '--' inside a single-quoted string", () => {
    const input = "select 'a -- b' as x;";
    assert.equal(blankLineComments(input), input);
  });
});

describe("parseFunctionSignatures", () => {
  test("detects a trailing default auth.uid() parameter", () => {
    const sql = "create function app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())\nreturns boolean\nlanguage sql;";
    const sigs = parseFunctionSignatures(sql);
    assert.equal(sigs.length, 1);
    assert.equal(sigs[0]?.name, "app.has_active_tenant_membership");
    assert.equal(sigs[0]?.paramCount, 2);
    assert.equal(sigs[0]?.defaultAuthFn, "uid");
  });

  test("does not flag a function with no default-auth parameter", () => {
    const sql = "create function app.is_supreme_admin()\nreturns boolean\nlanguage sql;";
    const sigs = parseFunctionSignatures(sql);
    assert.equal(sigs.length, 1);
    assert.equal(sigs[0]?.defaultAuthFn, null);
  });

  test("ignores a function name/signature that only appears inside a -- comment", () => {
    // Exactly the real false-positive this guard's own first draft hit against
    // supabase/migrations/20260730950000_harden_hris_attendance_batch_278_280_review_fixes.sql:
    // a comment mentioning "CREATE POLICY" is not a real policy statement.
    const sql =
      "-- DROP POLICY + CREATE POLICY for RLS, and a function signature\n" +
      "-- like app.fake_helper(p_auth_user_id uuid default auth.uid()) mentioned only in prose.\n" +
      "create function app.real_helper(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())\nreturns boolean language sql;";
    const sigs = parseFunctionSignatures(sql);
    assert.equal(sigs.length, 1);
    assert.equal(sigs[0]?.name, "app.real_helper");
  });

  test("handles multi-line parameter lists (the real shape used across ~35 migrations)", () => {
    const sql = "create function app.check_payroll_finance_handoff_view_authority(\n  p_tenant_id uuid,\n  p_actor_auth_user_id uuid default auth.uid()\n)\nreturns boolean language sql;";
    const sigs = parseFunctionSignatures(sql);
    assert.equal(sigs[0]?.paramCount, 2);
    assert.equal(sigs[0]?.defaultAuthFn, "uid");
  });
});

describe("parsePolicyStatements + findBareAuthCalls (check 1 -- the pre-existing regression guard)", () => {
  test("flags a bare, unwrapped auth.uid() inside a policy clause", () => {
    const sql = "create policy p on app.t\n  using (auth_user_id = auth.uid());";
    const [stmt] = parsePolicyStatements("f.sql", sql);
    assert.ok(stmt);
    const findings = findBareAuthCalls("f.sql", stmt!);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.authFn, "uid");
  });

  test("does not flag auth.uid() already wrapped in (select ...)", () => {
    const sql = "create policy p on app.t\n  using (auth_user_id = (select auth.uid()));";
    const [stmt] = parsePolicyStatements("f.sql", sql);
    assert.deepEqual(findBareAuthCalls("f.sql", stmt!), []);
  });

  test("does not flag a comment that merely mentions auth.uid()", () => {
    const sql = "-- policy uses auth.uid() conceptually\ncreate policy p on app.t\n  using (app.has_active_tenant_membership(tenant_id));";
    const [stmt] = parsePolicyStatements("f.sql", sql);
    assert.equal(stmt?.text.includes("create policy"), true);
    assert.deepEqual(findBareAuthCalls("f.sql", stmt!), []);
  });
});

describe("findHelperCallSites (check 2 -- ISS-2026-240's own new detection)", () => {
  const registry = parseFunctionSignatures("create function app.has_active_tenant_membership(p_tenant_id uuid, p_auth_user_id uuid default auth.uid())\nreturns boolean language sql;");

  test("classifies an omitted trailing default-auth arg as the informational blind spot", () => {
    const sql = "create policy p on app.t\n  using (app.has_active_tenant_membership(tenant_id));";
    const [stmt] = parsePolicyStatements("f.sql", sql);
    const findings = findHelperCallSites("f.sql", stmt!, registry);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "DEFAULT_PARAM_INITPLAN_BLIND_SPOT");
  });

  test("classifies an explicit (select auth.uid()) as already-safe", () => {
    const sql = "create policy p on app.t\n  using (app.has_active_tenant_membership(tenant_id, (select auth.uid())));";
    const [stmt] = parsePolicyStatements("f.sql", sql);
    const findings = findHelperCallSites("f.sql", stmt!, registry);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "EXPLICIT_HOISTED_SAFE");
  });

  test("classifies an explicit non-auth override as a real, separate finding", () => {
    const sql = "create policy p on app.t\n  using (app.has_active_tenant_membership(tenant_id, some_other_user_id));";
    const [stmt] = parsePolicyStatements("f.sql", sql);
    const findings = findHelperCallSites("f.sql", stmt!, registry);
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.kind, "UNEXPECTED_AUTH_PARAM_OVERRIDE");
  });
});

describe("scanRepository — live regression run against this repository's real migrations", () => {
  test("finds zero bare auth.*() regressions and zero unexpected default-auth-param overrides", () => {
    const result = scanRepository();
    assert.deepEqual(
      result.bareAuthRegressions.map((f) => `${f.file}:${f.line}`),
      [],
      "a bare, unwrapped auth.*() call was introduced into a policy clause -- see docs/runtime/KNOWN_ISSUES.md's original auth_rls_initplan fix",
    );
    assert.deepEqual(
      result.unexpectedOverrides.map((f) => `${f.file}:${f.line} ${f.functionName}`),
      [],
      "a policy supplied something other than (select auth.*()) for a helper function's own default-auth parameter -- possible identity-substitution defect, see ISS-2026-240",
    );
  });

  test("the ISS-2026-240 blind spot is real and present (documents the finding, does not regress it)", () => {
    const result = scanRepository();
    assert.ok(result.blindSpotUses.length > 0, "expected at least one default-auth-param call site inside a policy clause");
  });
});
