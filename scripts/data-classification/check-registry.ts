/**
 * Data-classification adoption gate — docs/standards/
 * DATA_CLASSIFICATION_STANDARDS.md §6/§7, CG-S5-PH0-016 (Prompt 95).
 *
 * Two checks: (1) PHASE_0_REGISTRY is internally valid (owner/level-floor/
 * duplicate rules, registry.ts's own validateRegistry()); (2) every
 * `secret`-classified variable in scripts/env/schema.ts's real, current
 * ENV_REGISTRY has a matching PHASE_0_REGISTRY entry — the first real
 * instance of the "no unclassified sensitive field ships" gate (Prompt 95
 * §23's exception flow), extended to `server/contracts/<domain>/` fields by
 * whichever Phase 1 prompt introduces the first one, not duplicated here.
 *
 * CLI: node --experimental-strip-types scripts/data-classification/check-registry.ts
 */

import { ENV_REGISTRY } from "../env/schema.ts";
import { validateRegistry, PHASE_0_REGISTRY, type ClassificationEntry, type RegistryViolation } from "./registry.ts";

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

function main(): void {
  const registryViolations: RegistryViolation[] = validateRegistry(PHASE_0_REGISTRY);
  const adoptionGaps = findUnclassifiedSecretEnvVars(ENV_REGISTRY, PHASE_0_REGISTRY);

  if (registryViolations.length === 0 && adoptionGaps.length === 0) {
    console.log("✔ data-classification registry is internally valid and every secret-classified env var is classified.");
    return;
  }

  for (const v of registryViolations) {
    console.error(`✖ registry entry "${v.id}" [${v.kind}]`);
  }
  for (const g of adoptionGaps) {
    console.error(`✖ env var "${g.envVarName}" [${g.kind}] — add a PHASE_0_REGISTRY entry with id "env:${g.envVarName}" before this ships`);
  }
  console.error(`\n${registryViolations.length + adoptionGaps.length} data-classification issue(s) — see docs/standards/DATA_CLASSIFICATION_STANDARDS.md §6/§7.`);
  process.exit(1);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
