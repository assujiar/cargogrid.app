import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  SENSITIVITY_LEVELS,
  compareLevel,
  strongest,
  CATEGORIES,
  CATEGORY_DEFAULT_LEVEL,
  CATEGORY_RETENTION_CLASS,
  HANDLING_MATRIX,
  validateRegistry,
  PHASE_0_REGISTRY,
  type ClassificationEntry,
} from "./registry.ts";

describe("compareLevel / strongest", () => {
  test("orders every level from weakest to strongest", () => {
    const sorted = [...SENSITIVITY_LEVELS].sort((a, b) => compareLevel(a, b));
    assert.deepEqual(sorted, ["public", "internal", "confidential", "restricted", "credential"]);
  });

  test("strongest resolves multiple sensitivities to the maximum (Prompt 95 §22)", () => {
    assert.equal(strongest(["public", "confidential", "internal"]), "confidential");
    assert.equal(strongest(["credential", "public"]), "credential");
  });

  test("strongest of a single level is itself", () => {
    assert.equal(strongest(["restricted"]), "restricted");
  });

  test("strongest rejects an empty list rather than returning a silent default", () => {
    assert.throws(() => strongest([]), /non-empty/);
  });

  test("credential is the ceiling — stronger than every other level", () => {
    for (const level of SENSITIVITY_LEVELS) {
      if (level === "credential") continue;
      assert.ok(compareLevel("credential", level) > 0);
    }
  });

  test("public is the floor — weaker than every other level", () => {
    for (const level of SENSITIVITY_LEVELS) {
      if (level === "public") continue;
      assert.ok(compareLevel("public", level) < 0);
    }
  });
});

describe("CATEGORY_DEFAULT_LEVEL", () => {
  test("every category has a default level", () => {
    for (const category of CATEGORIES) {
      assert.ok(SENSITIVITY_LEVELS.includes(CATEGORY_DEFAULT_LEVEL[category]));
    }
  });

  test("security_credential defaults to the ceiling level (02_*.md §10: masked always)", () => {
    assert.equal(CATEGORY_DEFAULT_LEVEL.security_credential, "credential");
  });

  test("finance and payroll default to restricted (02_*.md §10 named-role defaults)", () => {
    assert.equal(CATEGORY_DEFAULT_LEVEL.finance, "restricted");
    assert.equal(CATEGORY_DEFAULT_LEVEL.payroll, "restricted");
  });
});

describe("CATEGORY_RETENTION_CLASS", () => {
  test("every category maps to a retention class", () => {
    for (const category of CATEGORIES) {
      assert.ok(CATEGORY_RETENTION_CLASS[category]);
    }
  });

  test("finance maps to the 10-year finance/tax class (RPD-025)", () => {
    assert.equal(CATEGORY_RETENTION_CLASS.finance, "finance_tax_10y");
  });
});

describe("HANDLING_MATRIX", () => {
  test("every level has a handling rule", () => {
    for (const level of SENSITIVITY_LEVELS) {
      assert.ok(HANDLING_MATRIX[level]);
    }
  });

  test("credential is never exportable (02_*.md §10: never exported plain)", () => {
    assert.equal(HANDLING_MATRIX.credential.exportable, false);
  });

  test("public and internal are visible by default and not maskable", () => {
    assert.equal(HANDLING_MATRIX.public.visibleByDefault, true);
    assert.equal(HANDLING_MATRIX.public.maskable, false);
    assert.equal(HANDLING_MATRIX.internal.visibleByDefault, true);
  });

  test("confidential, restricted, and credential all require audit", () => {
    assert.equal(HANDLING_MATRIX.confidential.auditRequired, true);
    assert.equal(HANDLING_MATRIX.restricted.auditRequired, true);
    assert.equal(HANDLING_MATRIX.credential.auditRequired, true);
  });
});

describe("validateRegistry", () => {
  test("accepts a well-formed entry at its category's default level", () => {
    const entries: ClassificationEntry[] = [{ id: "test:field", category: "pii", level: "confidential", owner: "Security", description: "test" }];
    assert.deepEqual(validateRegistry(entries), []);
  });

  test("accepts an entry declared stronger than its category default", () => {
    const entries: ClassificationEntry[] = [{ id: "test:field", category: "pii", level: "restricted", owner: "Security", description: "test" }];
    assert.deepEqual(validateRegistry(entries), []);
  });

  test("flags an entry declared weaker than its category default", () => {
    const entries: ClassificationEntry[] = [{ id: "test:field", category: "finance", level: "internal", owner: "Finance", description: "test" }];
    const violations = validateRegistry(entries);
    assert.equal(violations.length, 1);
    assert.equal(violations[0]?.kind, "LEVEL_BELOW_CATEGORY_DEFAULT");
  });

  test("flags a missing owner", () => {
    const entries: ClassificationEntry[] = [{ id: "test:field", category: "pii", level: "confidential", owner: "", description: "test" }];
    const violations = validateRegistry(entries);
    assert.equal(violations.length, 1);
    assert.equal(violations[0]?.kind, "MISSING_OWNER");
  });

  test("flags an owner that is only whitespace", () => {
    const entries: ClassificationEntry[] = [{ id: "test:field", category: "pii", level: "confidential", owner: "   ", description: "test" }];
    assert.equal(validateRegistry(entries)[0]?.kind, "MISSING_OWNER");
  });

  test("flags a duplicate id", () => {
    const entries: ClassificationEntry[] = [
      { id: "test:field", category: "pii", level: "confidential", owner: "Security", description: "first" },
      { id: "test:field", category: "pii", level: "confidential", owner: "Security", description: "second" },
    ];
    const violations = validateRegistry(entries);
    assert.equal(violations.filter((v) => v.kind === "DUPLICATE_ID").length, 1);
  });

  test("an entry can carry multiple violations at once", () => {
    const entries: ClassificationEntry[] = [{ id: "test:field", category: "finance", level: "public", owner: "", description: "test" }];
    const violations = validateRegistry(entries);
    const kinds = violations.map((v) => v.kind).sort();
    assert.deepEqual(kinds, ["LEVEL_BELOW_CATEGORY_DEFAULT", "MISSING_OWNER"]);
  });

  test("empty registry has no violations", () => {
    assert.deepEqual(validateRegistry([]), []);
  });
});

describe("PHASE_0_REGISTRY — this repository's real, current classified assets", () => {
  test("is internally valid", () => {
    assert.deepEqual(validateRegistry(PHASE_0_REGISTRY), []);
  });

  test("contains the one real secret-classified environment variable", () => {
    const entry = PHASE_0_REGISTRY.find((e) => e.id === "env:SUPABASE_SERVICE_ROLE_KEY");
    assert.ok(entry);
    assert.equal(entry.category, "security_credential");
    assert.equal(entry.level, "credential");
  });
});
