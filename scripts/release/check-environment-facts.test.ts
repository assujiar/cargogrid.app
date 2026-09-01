import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { findAssertionDrift, findLiveDrift, type EnvironmentFacts, type RepoConfigSnapshot } from "./check-environment-facts.ts";

function facts(overrides: Partial<EnvironmentFacts> = {}): EnvironmentFacts {
  return {
    vercel: { projectId: "prj_test", teamSlug: "team-test", productionAutoDeployGated: true },
    supabase: { projectRef: "ref_test", organizationId: "org_test" },
    nodeVersion: { pinned: "24.x" },
    ...overrides,
  };
}

function config(overrides: Partial<RepoConfigSnapshot> = {}): RepoConfigSnapshot {
  return {
    vercelJson: { git: { deploymentEnabled: { main: false } }, ignoreCommand: "node scripts/release/check-go-decision.ts" },
    packageJsonEngineNode: "24.x",
    ...overrides,
  };
}

const kinds = (findings: readonly { kind: string }[]) => findings.map((f) => f.kind);

describe("findAssertionDrift", () => {
  test("a consistent repository produces no findings", () => {
    assert.deepEqual(findAssertionDrift(facts(), config()), []);
  });

  test("THE ISS-2026-284 SHAPE: gated is declared but vercel.json does not gate it", () => {
    assert.deepEqual(
      kinds(findAssertionDrift(facts(), config({ vercelJson: { git: { deploymentEnabled: { main: true } }, ignoreCommand: "node scripts/release/check-go-decision.ts" } }))),
      ["vercel_deploy_gate_mismatch"],
    );
  });

  test("gated is declared but vercel.json does not exist at all", () => {
    assert.deepEqual(kinds(findAssertionDrift(facts(), config({ vercelJson: null }))), ["vercel_config_missing"]);
  });

  test("gated is declared, main is false, but the ignoreCommand does not reference the go-decision gate", () => {
    assert.deepEqual(
      kinds(findAssertionDrift(facts(), config({ vercelJson: { git: { deploymentEnabled: { main: false } }, ignoreCommand: "echo hi" } }))),
      ["vercel_ignore_command_missing"],
    );
  });

  test("productionAutoDeployGated=false skips the vercel.json checks entirely -- an ungated declaration is not itself a finding", () => {
    assert.deepEqual(findAssertionDrift(facts({ vercel: { projectId: "p", teamSlug: "t", productionAutoDeployGated: false } }), config({ vercelJson: null })), []);
  });

  test("a Node version mismatch is reported", () => {
    assert.deepEqual(kinds(findAssertionDrift(facts(), config({ packageJsonEngineNode: "22.x" }))), ["node_version_mismatch"]);
  });

  test("an absent engines.node is not itself a mismatch -- some repos legitimately omit the pin", () => {
    assert.deepEqual(findAssertionDrift(facts(), config({ packageJsonEngineNode: undefined })), []);
  });

  test("multiple independent findings are all reported, not just the first", () => {
    assert.deepEqual(kinds(findAssertionDrift(facts(), config({ vercelJson: null, packageJsonEngineNode: "20.x" }))), ["vercel_config_missing", "node_version_mismatch"]);
  });
});

describe("findLiveDrift", () => {
  test("both providers found: no findings", () => {
    assert.deepEqual(findLiveDrift(facts(), { vercelProjectFound: true, supabaseProjectFound: true }), []);
  });

  test("THE STEP-15 SHAPE: a project silently moved or was deleted", () => {
    assert.deepEqual(kinds(findLiveDrift(facts(), { vercelProjectFound: false, supabaseProjectFound: true })), ["vercel_project_not_found"]);
  });

  test("both providers missing are both reported", () => {
    assert.deepEqual(kinds(findLiveDrift(facts(), { vercelProjectFound: false, supabaseProjectFound: false })), ["vercel_project_not_found", "supabase_project_not_found"]);
  });

  test("the finding names the exact declared id so an operator knows what to re-check", () => {
    const findings = findLiveDrift(facts(), { vercelProjectFound: false, supabaseProjectFound: true });
    assert.match(findings[0]?.detail ?? "", /prj_test/);
    assert.match(findings[0]?.detail ?? "", /team-test/);
  });
});
