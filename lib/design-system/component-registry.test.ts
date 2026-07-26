import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { COMPONENT_REGISTRY, CATEGORY_LABELS } from "./component-registry.ts";

describe("COMPONENT_REGISTRY", () => {
  test("every entry name is unique", () => {
    const names = COMPONENT_REGISTRY.map((entry) => entry.name);
    assert.equal(new Set(names).size, names.length);
  });

  test("every entry's category has a label", () => {
    for (const entry of COMPONENT_REGISTRY) {
      assert.ok(CATEGORY_LABELS[entry.category], `${entry.name}: unknown category "${entry.category}"`);
    }
  });

  test("productionReady is true only for IMPLEMENTED entries", () => {
    for (const entry of COMPONENT_REGISTRY) {
      if (entry.productionReady) {
        assert.equal(entry.status, "IMPLEMENTED", `${entry.name}: productionReady=true but status is ${entry.status}`);
      }
    }
  });

  test("every IMPLEMENTED entry has a sourceFile and importSnippet", () => {
    for (const entry of COMPONENT_REGISTRY) {
      if (entry.status === "IMPLEMENTED") {
        assert.ok(entry.sourceFile, `${entry.name}: missing sourceFile`);
        assert.ok(entry.importSnippet, `${entry.name}: missing importSnippet`);
      }
    }
  });

  test("every entry has a non-empty citation", () => {
    for (const entry of COMPONENT_REGISTRY) {
      assert.ok(entry.citation && entry.citation.length > 0, `${entry.name}: missing citation`);
    }
  });

  test("at least 6 IMPLEMENTED entries exist (the real primitives)", () => {
    const implemented = COMPONENT_REGISTRY.filter((entry) => entry.status === "IMPLEMENTED");
    assert.ok(implemented.length >= 6, `expected at least 6 IMPLEMENTED entries, found ${implemented.length}`);
  });
});
