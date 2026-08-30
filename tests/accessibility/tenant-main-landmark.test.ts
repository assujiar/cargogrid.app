import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";

/**
 * Regression guard for `ISS-2026-241`.
 *
 * 36 of the 38 tenant module trees rendered with no `<main>` (or `role="main"`) anywhere,
 * so a screen-reader user had nothing to jump to and had to arrow through the repeated
 * chrome on every page load — WCAG 2.2 AA 1.3.1 and 2.4.1.
 *
 * The fix was 36 tiny layout files, which is exactly the kind of fix that decays: the next
 * module someone adds will not have one, and nothing would notice. This test is the thing
 * that notices. It is deliberately a *structural* check against the real file tree rather
 * than a snapshot of the 38 modules that exist today — a snapshot would pass forever while
 * new modules quietly arrived without a landmark.
 */

const TENANT_ROOT = "app/(tenant)/[tenantSlug]";

function moduleDirectories(): string[] {
  return readdirSync(TENANT_ROOT)
    .filter((entry) => statSync(join(TENANT_ROOT, entry)).isDirectory())
    .sort();
}

/**
 * Structural checks below must look at code, not prose. Several of these files *discuss*
 * `<main>` in their own header comments, and the first version of this test both failed on
 * the tenant shell's comment and — worse — would have let a module pass on a comment alone,
 * making the guard weaker than it appeared. Comments are stripped first.
 */
function code(path: string): string {
  return readFileSync(path, "utf8")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
}

describe("ISS-2026-241: every tenant module renders a main landmark", () => {
  test("the tenant shell exists and provides a skip link", () => {
    const shell = join(TENANT_ROOT, "layout.tsx");
    assert.ok(existsSync(shell), `${shell} must exist — it owns the skip link for every tenant route`);
    const source = code(shell);
    assert.match(source, /SkipToContentLink/, "the tenant shell must render the skip link");
    // The shell must NOT own a <main>: it wraps admin/ and commercial/, whose own layouts
    // render site navigation. A <main> here would put that navigation inside the landmark
    // that exists to let you skip past it.
    assert.doesNotMatch(
      source,
      /<main[\s>]/,
      "the tenant shell must not render <main> — it would wrap the module navs that admin/ and commercial/ render",
    );
  });

  test("the skip link targets the same anchor the landmark exposes", () => {
    const link = code("components/layout/skip-to-content-link.tsx");
    const main = code("components/layout/tenant-main.tsx");
    assert.match(link, /href="#main-content"/, "the skip link must target #main-content");
    assert.match(main, /id="main-content"/, "the landmark must expose #main-content");
    // Without a focusable target the link scrolls but leaves focus in the nav, which is the
    // bug that makes skip links feel broken to the people who rely on them.
    assert.match(main, /tabIndex=\{-1\}/, "the landmark must be programmatically focusable");
  });

  test("every module directory has a layout that renders a main landmark", () => {
    const modules = moduleDirectories();
    assert.ok(modules.length >= 38, `expected at least 38 tenant modules, found ${modules.length}`);

    const missing: string[] = [];
    for (const moduleName of modules) {
      const layout = join(TENANT_ROOT, moduleName, "layout.tsx");
      if (!existsSync(layout)) {
        missing.push(`${moduleName}: no layout.tsx`);
        continue;
      }
      const source = code(layout);
      const rendersLandmark = /TenantMain/.test(source) || /<main[\s>]/.test(source) || /role="main"/.test(source);
      if (!rendersLandmark) {
        missing.push(`${moduleName}: layout.tsx renders no <main>, role="main" or TenantMain`);
      }
    }

    assert.deepEqual(
      missing,
      [],
      `every tenant module must render a main landmark (ISS-2026-241). Missing:\n  ${missing.join("\n  ")}`,
    );
  });

  test("the two modules with their own chrome anchor the skip link themselves", () => {
    // admin/ and commercial/ render their own header and nav, so they cannot use TenantMain
    // (which would place the landmark before their chrome). They carry the anchor directly,
    // and this asserts they did not lose it — including on their access-denied render, which
    // is a real page a user can land on and must still be skippable.
    for (const moduleName of ["admin", "commercial"]) {
      const source = code(join(TENANT_ROOT, moduleName, "layout.tsx"));
      const mains = source.match(/<main[\s>]/g) ?? [];
      const anchored = source.match(/id="main-content"/g) ?? [];
      assert.ok(mains.length > 0, `${moduleName}/layout.tsx must render <main>`);
      assert.equal(
        anchored.length,
        mains.length,
        `every <main> in ${moduleName}/layout.tsx must carry id="main-content" — including the access-denied render`,
      );
    }
  });
});
