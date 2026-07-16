/**
 * Data classification registry — docs/standards/DATA_CLASSIFICATION_STANDARDS.md
 * §2–§6, CG-S5-PH0-016 (Prompt 95). Sensitivity-level scale and
 * strongest-resolution rule are this checkpoint's own construction from
 * docs/architecture/02_CANONICAL_DATA_FLOW_MAP.md §10's prose defaults
 * (disclosed, §1 of the standards doc); categories and retention mapping are
 * reproduced from that same §10/§11, not re-derived.
 */

export const SENSITIVITY_LEVELS = ["public", "internal", "confidential", "restricted", "credential"] as const;
export type SensitivityLevel = (typeof SENSITIVITY_LEVELS)[number];

const LEVEL_ORDER: Record<SensitivityLevel, number> = {
  public: 0,
  internal: 1,
  confidential: 2,
  restricted: 3,
  credential: 4,
};

/** Total ordering: negative if `a` is weaker than `b`, positive if stronger, 0 if equal. */
export function compareLevel(a: SensitivityLevel, b: SensitivityLevel): number {
  return LEVEL_ORDER[a] - LEVEL_ORDER[b];
}

/** docs/standards/DATA_CLASSIFICATION_STANDARDS.md §2 — Prompt 95 §22's "strongest applicable handling" rule. */
export function strongest(levels: readonly SensitivityLevel[]): SensitivityLevel {
  if (levels.length === 0) {
    throw new Error("strongest: levels must be non-empty");
  }
  return levels.reduce((max, level) => (compareLevel(level, max) > 0 ? level : max));
}

export const CATEGORIES = ["cost_margin", "finance", "payroll", "pii", "security_credential", "support"] as const;
export type Category = (typeof CATEGORIES)[number];

/** docs/standards/DATA_CLASSIFICATION_STANDARDS.md §1's disclosed mapping from 02_*.md §10's 6 field groups. */
export const CATEGORY_DEFAULT_LEVEL: Record<Category, SensitivityLevel> = {
  cost_margin: "confidential",
  pii: "confidential",
  finance: "restricted",
  payroll: "restricted",
  support: "restricted",
  security_credential: "credential",
};

export type RetentionClass = "finance_tax_10y" | "audit_security_7y" | "operational_contract_plus_90d";

/** docs/standards/DATA_CLASSIFICATION_STANDARDS.md §5 (RPD-025, docs/architecture/02_*.md §11). */
export const CATEGORY_RETENTION_CLASS: Record<Category, RetentionClass> = {
  finance: "finance_tax_10y",
  payroll: "finance_tax_10y", // disclosed inference, not an itemized RPD-025 row — see standards doc §5
  security_credential: "audit_security_7y",
  support: "audit_security_7y",
  cost_margin: "operational_contract_plus_90d",
  pii: "operational_contract_plus_90d",
};

export interface HandlingRule {
  readonly visibleByDefault: boolean;
  readonly maskable: boolean;
  readonly exportable: boolean;
  readonly auditRequired: boolean;
}

/** docs/standards/DATA_CLASSIFICATION_STANDARDS.md §4 — the 4 machine-checkable columns of the 8-dimension matrix (the remaining 4 — editability, printability, filterability, API exposure — are role/context-dependent and enforced by the Phase 1 policy engine, not this static table). */
export const HANDLING_MATRIX: Record<SensitivityLevel, HandlingRule> = {
  public: { visibleByDefault: true, maskable: false, exportable: true, auditRequired: false },
  internal: { visibleByDefault: true, maskable: false, exportable: true, auditRequired: false },
  confidential: { visibleByDefault: false, maskable: true, exportable: true, auditRequired: true },
  restricted: { visibleByDefault: false, maskable: true, exportable: true, auditRequired: true },
  credential: { visibleByDefault: false, maskable: true, exportable: false, auditRequired: true },
};

export interface ClassificationEntry {
  readonly id: string;
  readonly category: Category;
  readonly level: SensitivityLevel;
  readonly owner: string;
  readonly description: string;
}

export type RegistryViolationKind = "MISSING_OWNER" | "LEVEL_BELOW_CATEGORY_DEFAULT" | "DUPLICATE_ID";

export interface RegistryViolation {
  readonly id: string;
  readonly kind: RegistryViolationKind;
}

/** docs/standards/DATA_CLASSIFICATION_STANDARDS.md §6 — Prompt 95 §25's validation rules. */
export function validateRegistry(entries: readonly ClassificationEntry[]): RegistryViolation[] {
  const violations: RegistryViolation[] = [];
  const seenIds = new Set<string>();
  for (const entry of entries) {
    if (seenIds.has(entry.id)) {
      violations.push({ id: entry.id, kind: "DUPLICATE_ID" });
    }
    seenIds.add(entry.id);

    if (entry.owner.trim().length === 0) {
      violations.push({ id: entry.id, kind: "MISSING_OWNER" });
    }

    const floor = CATEGORY_DEFAULT_LEVEL[entry.category];
    if (compareLevel(entry.level, floor) < 0) {
      violations.push({ id: entry.id, kind: "LEVEL_BELOW_CATEGORY_DEFAULT" });
    }
  }
  return violations;
}

/**
 * This repository's actual Phase 0 assets, classified — docs/standards/
 * DATA_CLASSIFICATION_STANDARDS.md §6/§7. Extended by each future capability
 * prompt that introduces a new sensitive field/variable, never
 * retroactively invented for a field that does not exist yet.
 */
export const PHASE_0_REGISTRY: readonly ClassificationEntry[] = [
  {
    id: "env:SUPABASE_SERVICE_ROLE_KEY",
    category: "security_credential",
    level: "credential",
    owner: "Platform/Security",
    description: "Supabase service-role key (scripts/env/schema.ts) — server-only, never sent to the browser bundle.",
  },
];
