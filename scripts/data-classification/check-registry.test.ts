import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  findUnclassifiedSecretEnvVars,
  parseSeededProtectedFinActions,
  findEnforcedProtectedFinActions,
  findUnclassifiedProtectedFinActions,
  REGISTRY,
} from "./check-registry.ts";
import { ENV_REGISTRY } from "../env/schema.ts";
import { PHASE_0_REGISTRY, FINANCE_REGISTRY, type ClassificationEntry } from "./registry.ts";

const MIGRATIONS_DIR = join(dirname(fileURLToPath(import.meta.url)), "../../supabase/migrations");

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

describe("parseSeededProtectedFinActions", () => {
  test("extracts exactly View cost and View margin from the real seeded permission catalog (regression guard)", () => {
    const source = readFileSync(join(MIGRATIONS_DIR, "20260716103445_create_roles_permissions.sql"), "utf8");
    assert.deepEqual(parseSeededProtectedFinActions(source).sort(), ["View cost", "View margin"]);
  });

  test("ignores an unprotected (false) FIN row and a protected row from a different module", () => {
    const source = "insert into app.permissions (action, resource_module_code, category, protected) values ('View', 'FIN', 'standard', false), ('View cost', 'OPS', 'sensitive', true), ('Approve', 'FIN', 'sensitive', true);";
    assert.deepEqual(parseSeededProtectedFinActions(source), ["Approve"]);
  });

  test("an empty source produces no actions", () => {
    assert.deepEqual(parseSeededProtectedFinActions(""), []);
  });
});

describe("findEnforcedProtectedFinActions", () => {
  test("keeps only an action a real Finance migration actually references by name", () => {
    const source = "if not app.has_view_finance_margin(...) then ... 'View margin' ...";
    assert.deepEqual(findEnforcedProtectedFinActions(["View cost", "View margin"], source), ["View margin"]);
  });

  test("View cost is currently unenforced by any real Finance migration (disclosed, Operations-only so far)", () => {
    const files = readdirSync(MIGRATIONS_DIR).filter((f) => f.includes("finance"));
    const source = files.map((f) => readFileSync(join(MIGRATIONS_DIR, f), "utf8")).join("\n");
    assert.deepEqual(findEnforcedProtectedFinActions(["View cost", "View margin"], source), ["View margin"]);
  });
});

describe("findUnclassifiedProtectedFinActions", () => {
  test("finds zero gaps for View margin against this repository's real FINANCE_REGISTRY (regression guard)", () => {
    assert.deepEqual(findUnclassifiedProtectedFinActions(["View margin"], REGISTRY), []);
  });

  test("flags an enforced action with no matching protectedAction registry entry", () => {
    const gaps = findUnclassifiedProtectedFinActions(["View margin", "Some New Action"], PHASE_0_REGISTRY);
    assert.equal(gaps.length, 2);
    assert.ok(gaps.some((g) => g.action === "Some New Action"));
  });

  test("does not flag an action once it is registered via protectedAction", () => {
    const registry: ClassificationEntry[] = [
      { id: "fin:test.figures", category: "cost_margin", level: "restricted", owner: "Finance", description: "test", protectedAction: "FIN:View margin" },
    ];
    assert.deepEqual(findUnclassifiedProtectedFinActions(["View margin"], registry), []);
  });
});

describe("FINANCE_REGISTRY", () => {
  test("is internally valid and adds no duplicate id against PHASE_0_REGISTRY", () => {
    const ids = new Set(PHASE_0_REGISTRY.map((e) => e.id));
    for (const entry of FINANCE_REGISTRY) {
      assert.equal(ids.has(entry.id), false, `duplicate id ${entry.id}`);
    }
  });
});
