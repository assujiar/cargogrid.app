import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { TOKEN_CATEGORIES } from "./tokens.ts";

const globalsCss = readFileSync(new URL("../../app/globals.css", import.meta.url), "utf8");

describe("TOKEN_CATEGORIES", () => {
  test("every IMPLEMENTED category's CSS custom properties actually exist in app/globals.css (no drift)", () => {
    for (const category of TOKEN_CATEGORIES) {
      if (category.status !== "IMPLEMENTED") {
        continue;
      }
      for (const item of category.items) {
        if (!item.cssVar.startsWith("--")) {
          continue;
        }
        assert.ok(
          globalsCss.includes(item.cssVar),
          `${category.key}: "${item.cssVar}" not found in app/globals.css -- update tokens.ts or globals.css`,
        );
      }
    }
  });

  test("NOT_DECIDED categories carry no items (nothing to fabricate a swatch for)", () => {
    for (const category of TOKEN_CATEGORIES) {
      if (category.status === "NOT_DECIDED") {
        assert.deepEqual(category.items, [], `${category.key} is NOT_DECIDED but has items`);
      }
    }
  });

  test("every category has a unique key", () => {
    const keys = TOKEN_CATEGORIES.map((category) => category.key);
    assert.equal(new Set(keys).size, keys.length);
  });
});
