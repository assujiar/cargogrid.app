/**
 * Preflight environment check — CargoGrid local development CLI entrypoint.
 *
 * Originally written at Prompt 85 (Development Environment Foundation) as a
 * standalone script; superseded in substance by the typed, classified
 * validation module built at Prompt 86 (Environment Validation Foundation,
 * CG-S5-PH0-007) in `scripts/env/`. This file now only wires that module to
 * the CLI (`pnpm run preflight`), preserving the exact command name/behavior
 * contract from Prompt 85 so existing local setup instructions keep working
 * unchanged (Prompt 86 §29 regression: "Local bootstrap ... remain functional").
 */

import { loadEnv, EnvValidationError, summarizeForAudit } from "./env/validate.ts";

function main(): void {
  try {
    const env = loadEnv();
    console.log(`✔ preflight-env-check passed for environment "${env.environmentClass}":`);
    for (const line of summarizeForAudit(env)) {
      console.log(`  - ${line}`);
    }
  } catch (error) {
    if (error instanceof EnvValidationError) {
      console.error(`\n✖ preflight-env-check failed:\n${error.message}\n`);
      console.error("  See .env.example for the required variable list and README.md \"Local development\" for setup steps.\n");
      process.exit(1);
    }
    throw error;
  }
}

main();
