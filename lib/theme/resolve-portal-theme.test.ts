import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolvePortalTheme } from "./resolve-portal-theme.ts";

describe("resolvePortalTheme", () => {
  test("null brand (no tenant / resolution failed) falls back to the CargoGrid default atomically", () => {
    const result = resolvePortalTheme(null);
    assert.equal(result.source, "default");
    assert.deepEqual(result.cssVars, {});
    assert.equal(result.logoAssetUrl, null);
  });

  test("default-source brand (no tenant override published) emits no CSS overrides", () => {
    const result = resolvePortalTheme({ source: "default", tokens: {}, logoAssetUrl: null });
    assert.equal(result.source, "default");
    assert.deepEqual(result.cssVars, {});
    assert.equal(result.logoAssetUrl, null);
  });

  test("tenant brand with both tokens overrides both CSS variables", () => {
    const result = resolvePortalTheme({
      source: "tenant",
      tokens: { primary: "#123456", secondary: "#abcdef" },
      logoAssetUrl: "https://storage.example.test/acme/logo.png",
    });
    assert.equal(result.source, "tenant");
    assert.deepEqual(result.cssVars, { "--color-primary": "#123456", "--color-secondary": "#abcdef" });
    assert.equal(result.logoAssetUrl, "https://storage.example.test/acme/logo.png");
  });

  test("tenant brand with only primary set overrides only --color-primary", () => {
    const result = resolvePortalTheme({ source: "tenant", tokens: { primary: "#123456" }, logoAssetUrl: null });
    assert.deepEqual(result.cssVars, { "--color-primary": "#123456" });
  });

  test("tenant brand with no tokens (published but no color override) emits no CSS overrides but keeps the logo", () => {
    const result = resolvePortalTheme({
      source: "tenant",
      tokens: {},
      logoAssetUrl: "https://storage.example.test/acme/logo.png",
    });
    assert.equal(result.source, "tenant");
    assert.deepEqual(result.cssVars, {});
    assert.equal(result.logoAssetUrl, "https://storage.example.test/acme/logo.png");
  });
});
