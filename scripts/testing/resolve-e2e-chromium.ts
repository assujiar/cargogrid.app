/**
 * E2E Chromium executable override (ISS-2026-316).
 *
 * WHAT THE ENTRY GOT WRONG
 *
 *   The entry concluded "no e2e run is possible in this sandbox at all" because
 *   `/opt/pw-browsers` holds Chromium build 1194 (v141) while the pinned
 *   `@playwright/test@1.61.1` wants build 1228 (v149), and this environment's own setup
 *   instructions say not to run `playwright install` to fetch the matching one.
 *
 *   Every observable fact there is correct. The conclusion is not: Playwright does not
 *   require the exact pinned build to launch a browser — `launchOptions.executablePath` runs
 *   any Chromium-family binary you point it at. Pointing it at the sandbox's own build 1194
 *   runs the entire suite, axe-core accessibility specs included.
 *
 * WHY THIS IS OPT-IN, ENV-GATED, AND REFUSED UNDER CI
 *
 *   A local run on build 1194 is corroborating evidence on a DIFFERENT Chromium than the one
 *   CI actually gates on — useful for iterating in this sandbox, but not a substitute for the
 *   real gate. Making the override the default, or letting it silently activate in CI, would
 *   quietly narrow what CI is proving without anyone deciding that on purpose. So it activates
 *   only when a human (or this sandbox's own test invocation) explicitly sets
 *   `CARGOGRID_E2E_CHROMIUM_PATH`, and it is refused outright when `CI` is set — CI installs
 *   the pinned build itself (`.github/workflows/ci.yml`) and must keep testing that exact one.
 *
 * WHAT STILL CANNOT BE CLOSED HERE
 *
 *   This sandbox will still never hold the exact pinned Chromium build, and it holds no
 *   WebKit or Firefox binary at all — that residual belongs with `ISS-2026-244` and needs the
 *   container image rebuilt with those binaries, which is not something this override, or any
 *   code change, can substitute for.
 */

/**
 * Pure decision core, so the branch logic is testable without spawning a browser.
 *
 * @param env - the two environment variables this decision reads.
 * @param exists - injected rather than calling `fs.existsSync` directly, so a bad path can be
 *   simulated without touching the real filesystem.
 * @returns the executable path to launch with, or `undefined` to use Playwright's own default
 *   resolution (the pinned build).
 */
export function resolveE2eChromiumOverride(env: { CI?: string; CARGOGRID_E2E_CHROMIUM_PATH?: string }, exists: (path: string) => boolean): string | undefined {
  // CI first, unconditionally: CI installs and tests the exact pinned build, and no value of
  // the override variable may change that, even if someone sets it by accident in a CI secret.
  if (env["CI"]) return undefined;

  const requested = env["CARGOGRID_E2E_CHROMIUM_PATH"];
  if (!requested) return undefined;

  if (!exists(requested)) {
    // Fail loudly rather than silently falling back to the pinned build: a typo'd path here
    // must not quietly become "the suite ran fine" when it actually launched nothing this
    // variable named.
    throw new Error(
      `CARGOGRID_E2E_CHROMIUM_PATH is set to "${requested}", but no file exists there. ` +
        "Unset it to use Playwright's own pinned build, or point it at a real Chromium executable (e.g. /opt/pw-browsers/chromium).",
    );
  }

  return requested;
}
