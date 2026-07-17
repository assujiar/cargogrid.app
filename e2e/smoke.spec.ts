import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

/**
 * Foundation smoke suite — CG-S5-PH0-012, Prompt 91. Proves the Playwright +
 * @axe-core/playwright layer is correctly wired (docs/standards/
 * TESTING_STANDARDS.md §9), not a test of any real CargoGrid page or
 * component — none exists yet (docs/standards/DESIGN_SYSTEM.md §1). Every
 * fixture below is inline synthetic HTML, no external network call, no
 * tenant data (docs/architecture/10_TESTING_WORKSTREAM.md §4.2's
 * synthetic-only rule).
 */

const INACCESSIBLE_FIXTURE = `
<!doctype html>
<html>
  <head><title>Foundation smoke — inaccessible fixture</title></head>
  <body>
    <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBTAA7" />
    <button></button>
  </body>
</html>`;

const ACCESSIBLE_FIXTURE = `
<!doctype html>
<html lang="en">
  <head><title>Foundation smoke — accessible fixture</title></head>
  <body>
    <main>
      <h1>CargoGrid testing foundation</h1>
      <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBTAA7" alt="Decorative placeholder" />
      <button aria-label="Acknowledge">OK</button>
    </main>
  </body>
</html>`;

test.describe("axe-core wiring (ADR-0008)", () => {
  test("flags a deliberately inaccessible fixture — proves the checker actually runs", async ({ page }) => {
    await page.setContent(INACCESSIBLE_FIXTURE);
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations.length).toBeGreaterThan(0);
    const ruleIds = results.violations.map((v) => v.id);
    assertIncludesAny(ruleIds, ["image-alt", "button-name"]);
  });

  test("passes a corrected fixture — proves the checker is not vacuously failing", async ({ page }) => {
    await page.setContent(ACCESSIBLE_FIXTURE);
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });
});

test.describe("browser-automation layer (ADR-0007)", () => {
  test("launches, navigates, and interacts deterministically", async ({ page }) => {
    await page.setContent(`
      <!doctype html>
      <html lang="en">
        <head><title>Foundation smoke — interaction fixture</title></head>
        <body>
          <p id="status">idle</p>
          <button id="go">Go</button>
          <script>
            document.getElementById("go").addEventListener("click", function () {
              document.getElementById("status").textContent = "clicked";
            });
          </script>
        </body>
      </html>`);
    await expect(page.locator("#status")).toHaveText("idle");
    await page.locator("#go").click();
    await expect(page.locator("#status")).toHaveText("clicked");
  });
});

function assertIncludesAny(haystack: string[], anyOf: string[]): void {
  const found = anyOf.some((id) => haystack.includes(id));
  if (!found) {
    throw new Error(`Expected violations to include one of [${anyOf.join(", ")}], got [${haystack.join(", ")}]`);
  }
}
