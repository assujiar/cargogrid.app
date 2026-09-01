import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveE2eChromiumOverride } from "./resolve-e2e-chromium.ts";

const EXISTS_ALL = () => true;
const EXISTS_NONE = () => false;

describe("resolveE2eChromiumOverride", () => {
  test("no variable set: use Playwright's own pinned build", () => {
    assert.equal(resolveE2eChromiumOverride({}, EXISTS_ALL), undefined);
  });

  test("THE SANDBOX CASE: the variable set to a real path is used", () => {
    assert.equal(resolveE2eChromiumOverride({ CARGOGRID_E2E_CHROMIUM_PATH: "/opt/pw-browsers/chromium" }, EXISTS_ALL), "/opt/pw-browsers/chromium");
  });

  test("CI ALWAYS WINS: even with the variable set, CI never gets the override", () => {
    // CI installs and tests the exact pinned build. No value of this variable may change that.
    assert.equal(resolveE2eChromiumOverride({ CI: "true", CARGOGRID_E2E_CHROMIUM_PATH: "/opt/pw-browsers/chromium" }, EXISTS_ALL), undefined);
  });

  test("a path that does not exist throws rather than silently falling back", () => {
    // Falling back here would let a typo'd path look like a passing suite that never actually
    // launched the browser this variable named.
    assert.throws(() => resolveE2eChromiumOverride({ CARGOGRID_E2E_CHROMIUM_PATH: "/no/such/binary" }, EXISTS_NONE), /no file exists/);
  });

  test("the missing-path error names the exact variable and value, and suggests the fix", () => {
    try {
      resolveE2eChromiumOverride({ CARGOGRID_E2E_CHROMIUM_PATH: "/no/such/binary" }, EXISTS_NONE);
      assert.fail("expected a throw");
    } catch (error) {
      assert.match(String(error), /CARGOGRID_E2E_CHROMIUM_PATH/);
      assert.match(String(error), /\/no\/such\/binary/);
      assert.match(String(error), /Unset it/);
    }
  });

  test("CI with no override variable is the ordinary CI path -- no error, no override", () => {
    assert.equal(resolveE2eChromiumOverride({ CI: "true" }, EXISTS_NONE), undefined);
  });

  test("the exists check receives exactly the path the variable named", () => {
    let received: string | undefined;
    resolveE2eChromiumOverride({ CARGOGRID_E2E_CHROMIUM_PATH: "/opt/pw-browsers/chromium" }, (p) => {
      received = p;
      return true;
    });
    assert.equal(received, "/opt/pw-browsers/chromium");
  });
});
