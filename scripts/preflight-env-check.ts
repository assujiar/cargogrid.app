/**
 * Preflight environment check — CargoGrid local development.
 *
 * Prompt 85 (Development Environment Foundation, CG-S5-PH0-006) task #3:
 * "Add production-link/secret/preflight safeguards and deterministic local
 * database/seed flow."
 *
 * Run: `pnpm run preflight` (or `node --experimental-strip-types scripts/preflight-env-check.ts`)
 *
 * This script performs two checks before any dev/build/test command relies on
 * environment state:
 *   1. Required variables are present (fails fast with an actionable message,
 *      not a downstream stack trace from a library that assumes they exist).
 *   2. SUPABASE_URL/NEXT_PUBLIC_SUPABASE_URL resolves to a local/loopback host,
 *      unless ALLOW_NON_LOCAL_SUPABASE_URL=true is explicitly set — this is the
 *      production-link safeguard: a local dev environment must never point at a
 *      real tenant's Supabase project by accident (copy-paste from a teammate,
 *      stale shell export, etc).
 */

const REQUIRED_VARS = [
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
] as const;

const LOCAL_HOSTS = new Set(["127.0.0.1", "localhost", "::1"]);

function fail(message: string): never {
  console.error(`\n✖ preflight-env-check failed: ${message}\n`);
  console.error("  See .env.example for the required variable list and README.md \"Local development\" for setup steps.\n");
  process.exit(1);
}

function checkRequiredVars(): Record<string, string> {
  const missing: string[] = [];
  const values: Record<string, string> = {};

  for (const name of REQUIRED_VARS) {
    const value = process.env[name];
    if (!value) {
      missing.push(name);
    } else {
      values[name] = value;
    }
  }

  if (missing.length > 0) {
    fail(
      `missing required environment variable(s): ${missing.join(", ")}. ` +
        `Copy .env.example to .env.local, run \`supabase start\`, and fill in the printed values.`,
    );
  }

  return values;
}

function checkNotProductionLinked(values: Record<string, string>): void {
  const allowNonLocal = process.env.ALLOW_NON_LOCAL_SUPABASE_URL === "true";
  const rawUrl = values.NEXT_PUBLIC_SUPABASE_URL;
  if (!rawUrl) {
    // Unreachable in practice (checkRequiredVars already exits on missing vars),
    // but keeps this function sound under noUncheckedIndexedAccess without a cast.
    fail("NEXT_PUBLIC_SUPABASE_URL is unexpectedly absent after required-variable check.");
  }

  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    fail(`NEXT_PUBLIC_SUPABASE_URL is not a valid URL: "${rawUrl}"`);
  }

  const isLocal = LOCAL_HOSTS.has(parsed.hostname);

  if (!isLocal && !allowNonLocal) {
    fail(
      `NEXT_PUBLIC_SUPABASE_URL ("${rawUrl}") does not point at a local/loopback host. ` +
        `Local development must use the local Supabase stack (\`supabase start\`), never a real ` +
        `tenant's production project. If this is genuinely intentional (e.g. a shared remote ` +
        `sandbox project), set ALLOW_NON_LOCAL_SUPABASE_URL=true explicitly — this is not the default.`,
    );
  }
}

function main(): void {
  const values = checkRequiredVars();
  checkNotProductionLinked(values);
  console.log("✔ preflight-env-check passed: required variables present, Supabase URL is local (or explicitly allowed).");
}

main();
