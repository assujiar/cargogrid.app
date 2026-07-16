import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { findUnclassifiedSecretEnvVars } from "./check-registry.ts";
import { ENV_REGISTRY } from "../env/schema.ts";
import { PHASE_0_REGISTRY, type ClassificationEntry } from "./registry.ts";

describe("findUnclassifiedSecretEnvVars", () => {
  test("finds zero gaps against this repository's real env schema and registry (regression guard)", () => {
    assert.deepEqual(findUnclassifiedSecretEnvVars(ENV_REGISTRY, PHASE_0_REGISTRY), []);
  });

  test("flags a secret-classified env var with no matching registry entry", () => {
    const fakeEnvRegistry = [
      { name: "FAKE_SECRET_VAR", classification: "secret" as const, description: "test", schema: {} as never },
      ...ENV_REGISTRY,
    ];
    const gaps = findUnclassifiedSecretEnvVars(fakeEnvRegistry, PHASE_0_REGISTRY);
    assert.equal(gaps.length, 1);
    assert.equal(gaps[0]?.envVarName, "FAKE_SECRET_VAR");
    assert.equal(gaps[0]?.kind, "UNCLASSIFIED_SECRET_ENV_VAR");
  });

  test("does not flag a public/server-classified env var even with no registry entry", () => {
    const fakeEnvRegistry = [{ name: "FAKE_PUBLIC_VAR", classification: "public" as const, description: "test", schema: {} as never }];
    assert.deepEqual(findUnclassifiedSecretEnvVars(fakeEnvRegistry, PHASE_0_REGISTRY), []);
  });

  test("does not flag a secret var once it is registered", () => {
    const fakeEnvRegistry = [{ name: "FAKE_SECRET_VAR", classification: "secret" as const, description: "test", schema: {} as never }];
    const registry: ClassificationEntry[] = [
      { id: "env:FAKE_SECRET_VAR", category: "security_credential", level: "credential", owner: "Security", description: "test" },
    ];
    assert.deepEqual(findUnclassifiedSecretEnvVars(fakeEnvRegistry, registry), []);
  });

  test("an empty env registry produces no gaps", () => {
    assert.deepEqual(findUnclassifiedSecretEnvVars([], PHASE_0_REGISTRY), []);
  });
});
