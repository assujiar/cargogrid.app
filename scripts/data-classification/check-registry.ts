/**
 * Data-classification adoption gate — docs/standards/
 * DATA_CLASSIFICATION_STANDARDS.md §6/§7, CG-S5-PH0-016 (Prompt 95); extended by
 * FIN-214 (Financial Field-Level Security, CG-S9-FIN-025).
 *
 * Three checks: (1) the combined registry (PHASE_0_REGISTRY + FINANCE_REGISTRY) is
 * internally valid (owner/level-floor/duplicate rules, registry.ts's own
 * validateRegistry()); (2) every `secret`-classified variable in
 * scripts/env/schema.ts's real, current ENV_REGISTRY has a matching registry entry;
 * (3) every seeded `protected: true` Finance (`FIN`) permission action that at least
 * one real Finance migration actually enforces by name has a matching
 * `protectedAction` registry entry — closing Prompt 95 §23's "no unclassified
 * sensitive field ships" gate for `server/contracts/<domain>/` fields, the exact
 * extension §8 of the standards doc named as deferred to "each domain's own owning
 * Phase 1+ prompt."
 *
 * CLI: node --experimental-strip-types scripts/data-classification/check-registry.ts
 */

import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { ENV_REGISTRY } from "../env/schema.ts";
import {
  validateRegistry,
  PHASE_0_REGISTRY,
  FINANCE_REGISTRY,
  PROCUREMENT_REGISTRY,
  HRS_REGISTRY,
  PERFORMANCE_REGISTRY,
  TRAINING_REGISTRY,
  type ClassificationEntry,
  type RegistryViolation,
} from "./registry.ts";

export const REGISTRY: readonly ClassificationEntry[] = [...PHASE_0_REGISTRY, ...FINANCE_REGISTRY, ...PROCUREMENT_REGISTRY, ...HRS_REGISTRY, ...PERFORMANCE_REGISTRY, ...TRAINING_REGISTRY];

export type AdoptionGapKind = "UNCLASSIFIED_SECRET_ENV_VAR";

export interface AdoptionGap {
  readonly envVarName: string;
  readonly kind: AdoptionGapKind;
}

/** Prompt 95 §23: a secret-classified env var with no registry entry is an unresolved gap, not silently passed. */
export function findUnclassifiedSecretEnvVars(envRegistry: typeof ENV_REGISTRY, classificationRegistry: readonly ClassificationEntry[]): AdoptionGap[] {
  const classifiedEnvIds = new Set(classificationRegistry.map((e) => e.id));
  const gaps: AdoptionGap[] = [];
  for (const def of envRegistry) {
    if (def.classification !== "secret") continue;
    const expectedId = `env:${def.name}`;
    if (!classifiedEnvIds.has(expectedId)) {
      gaps.push({ envVarName: def.name, kind: "UNCLASSIFIED_SECRET_ENV_VAR" });
    }
  }
  return gaps;
}

/** Every `('<action>', 'FIN', ..., true)` row in the seeded permission catalog — statically parsed, not a live DB read (this script runs with no database connection). */
export function parseSeededProtectedFinActions(permissionCatalogSource: string): string[] {
  const actions: string[] = [];
  // Matches e.g. ('View cost', 'FIN', 'sensitive', true) across the seed migration's own multi-row `values (...)` literal.
  const rowPattern = /\(\s*'([^']+)'\s*,\s*'FIN'\s*,\s*'[^']*'\s*,\s*true\s*\)/g;
  for (const match of permissionCatalogSource.matchAll(rowPattern)) {
    const action = match[1];
    if (action) actions.push(action);
  }
  return actions;
}

/** A protected FIN action this repository's own migrations actually reference by name (`'<action>'` inside an `evaluate_permission`/`check_finance_*_authority` call) — only an *enforced* action needs registry coverage; a seeded-but-unused one (disclosed) does not yet. */
export function findEnforcedProtectedFinActions(protectedActions: readonly string[], financeMigrationsSource: string): string[] {
  return protectedActions.filter((action) => financeMigrationsSource.includes(`'${action}'`));
}

export type FinancePolicyGapKind = "UNCLASSIFIED_PROTECTED_FIN_ACTION";

export interface FinancePolicyGap {
  readonly action: string;
  readonly kind: FinancePolicyGapKind;
}

/** FIN-214 §7/§23: every protected FIN action a real Finance migration enforces must have a registry entry naming it as that entry's own `protectedAction`. */
export function findUnclassifiedProtectedFinActions(enforcedActions: readonly string[], classificationRegistry: readonly ClassificationEntry[]): FinancePolicyGap[] {
  const classifiedActions = new Set(classificationRegistry.map((e) => e.protectedAction).filter((a): a is string => Boolean(a)));
  return enforcedActions.filter((action) => !classifiedActions.has(`FIN:${action}`)).map((action) => ({ action, kind: "UNCLASSIFIED_PROTECTED_FIN_ACTION" as const }));
}

function loadPermissionCatalogSource(): string {
  return readFileSync(join(import.meta.dirname, "../../supabase/migrations/20260716103445_create_roles_permissions.sql"), "utf8");
}

function loadFinanceMigrationsSource(): string {
  const dir = join(import.meta.dirname, "../../supabase/migrations");
  return readdirSync(dir)
    .filter((f) => f.includes("finance"))
    .map((f) => readFileSync(join(dir, f), "utf8"))
    .join("\n");
}

function main(): void {
  const registryViolations: RegistryViolation[] = validateRegistry(REGISTRY);
  const adoptionGaps = findUnclassifiedSecretEnvVars(ENV_REGISTRY, REGISTRY);

  const protectedFinActions = parseSeededProtectedFinActions(loadPermissionCatalogSource());
  const enforcedFinActions = findEnforcedProtectedFinActions(protectedFinActions, loadFinanceMigrationsSource());
  const financePolicyGaps = findUnclassifiedProtectedFinActions(enforcedFinActions, REGISTRY);

  if (registryViolations.length === 0 && adoptionGaps.length === 0 && financePolicyGaps.length === 0) {
    console.log("✔ data-classification registry is internally valid, every secret-classified env var is classified, and every enforced protected Finance action is classified.");
    return;
  }

  for (const v of registryViolations) {
    console.error(`✖ registry entry "${v.id}" [${v.kind}]`);
  }
  for (const g of adoptionGaps) {
    console.error(`✖ env var "${g.envVarName}" [${g.kind}] — add a registry entry with id "env:${g.envVarName}" before this ships`);
  }
  for (const g of financePolicyGaps) {
    console.error(`✖ protected Finance action "FIN:${g.action}" [${g.kind}] — add a FINANCE_REGISTRY entry naming it as protectedAction before it ships`);
  }
  const total = registryViolations.length + adoptionGaps.length + financePolicyGaps.length;
  console.error(`\n${total} data-classification issue(s) — see docs/standards/DATA_CLASSIFICATION_STANDARDS.md §6/§7 and docs/standards/FINANCE_FIELD_POLICY_MATRIX.md.`);
  process.exit(1);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
