/**
 * Access gate for `/internal/design-system` (CargoGrid UI Modernization checkpoint 3).
 * The showcase must be reachable by an authorized internal user (Supreme Admin) in any
 * environment, and reachable by anyone in a non-production environment (so a local
 * engineer without a seeded Supreme Admin account can still see it). This module
 * decides only the second half -- "is this a non-production environment" -- as a pure
 * function of environment variables, so it is unit-testable without a request/session.
 *
 * Reads `CARGOGRID_ENV` first -- this repository's own deployment-tier discriminator
 * (`scripts/env/schema.ts`, one of `local|development|testing|staging|uat|production|
 * sandbox`), more precise than Node's own build-mode `NODE_ENV`. Falls back to
 * `NODE_ENV` only when `CARGOGRID_ENV` is unset (e.g. this sandbox, which has no `.env`
 * wired yet, `docs/runtime/CARGOGRID_BUILD_STATUS.md` §1).
 */

export interface EnvironmentTierVars {
  readonly CARGOGRID_ENV?: string;
  readonly NODE_ENV?: string;
}

export function isNonProductionEnvironment(env: EnvironmentTierVars = process.env): boolean {
  const tier = env.CARGOGRID_ENV;
  if (tier !== undefined) {
    return tier !== "production";
  }
  return env.NODE_ENV !== "production";
}
