import next from "eslint-config-next";
import importPlugin from "eslint-plugin-import";

// Coding standards and architecture enforcement — CG-S5-PH0-010, Prompt 89.
// See docs/standards/CODING_STANDARDS.md for the full rationale and citations.
// Every rule below was proven to fire against a real fixture violation this
// checkpoint (docs/build-log/phase-00/PH0-89.md §5), not merely configured.

// docs/standards/CODING_STANDARDS.md §2 rules 1-2: platform kernel never
// depends on a business domain; no business domain depends on CPT/REP.
// Inert today (lib/, server/ don't exist until Phase 1) — fires the moment
// those paths are created, same "establish now" pattern as ADR-0001 and
// scripts/git/check-protected-paths.ts.
const boundaryRules = {
  plugins: { import: importPlugin },
  rules: {
    "import/no-restricted-paths": [
      "error",
      {
        zones: [
          {
            target: ["./lib/**", "./server/policies/**"],
            from: [
              "./server/queries/com*.ts",
              "./server/queries/ops*.ts",
              "./server/queries/fin*.ts",
              "./server/queries/prc*.ts",
              "./server/queries/hrs*.ts",
              "./server/queries/tkt*.ts",
              "./server/queries/cpt*.ts",
              "./server/queries/lyl*.ts",
              "./app/(tenant)/**",
              "./app/(customer)/**",
            ],
            message:
              "Platform kernel (lib/, server/policies/) must never depend on a business domain (docs/standards/CODING_STANDARDS.md §2 rule 1, docs/architecture/03_DOMAIN_BOUNDARY_MAP.md §4).",
          },
          {
            target: [
              "./server/queries/com*.ts",
              "./server/queries/ops*.ts",
              "./server/queries/fin*.ts",
              "./server/queries/prc*.ts",
              "./server/queries/hrs*.ts",
              "./server/queries/tkt*.ts",
              "./server/queries/lyl*.ts",
            ],
            from: ["./server/queries/cpt*.ts", "./server/queries/rep*.ts"],
            message:
              "No business domain may depend on CPT or REP — both are strictly downstream/leaf nodes (docs/standards/CODING_STANDARDS.md §2 rule 2, docs/architecture/03_DOMAIN_BOUNDARY_MAP.md §4).",
          },
        ],
      },
    ],
  },
};

// docs/standards/CODING_STANDARDS.md §10/§11. Both selectors MUST live in one
// "no-restricted-syntax" rule array, not two separate config objects — ESLint
// flat config replaces (does not merge) a rule's value when two matching
// config objects both set the same rule key, so a second object setting
// "no-restricted-syntax" would silently discard the first's selector. Found
// and fixed during authoring this checkpoint (docs/build-log/phase-00/PH0-89.md
// §5) — proven with --print-config showing the SELECT * selector missing
// before this fix. No `ignores` exemption is needed for the service-role
// selector: scripts/env/** reads variables via computed bracket access
// (`source[def.name]`), never the literal dot-access this selector matches
// (verified: zero matches for the literal form anywhere in scripts/).
const bannedPatterns = {
  rules: {
    "no-restricted-syntax": [
      "error",
      {
        selector: "Literal[value=/SELECT\\s+\\*/i], TemplateElement[value.raw=/SELECT\\s+\\*/i]",
        // Message deliberately avoids spelling "SELECT" + whitespace + "*" together — this rule's own
        // error message would otherwise match its own selector (found for real this checkpoint, see
        // docs/build-log/phase-00/PH0-89.md §5).
        message: "No wildcard column SELECT (NFR-PERF-002, docs/standards/CODING_STANDARDS.md §11) — select exact columns instead of every column.",
      },
      {
        selector: "MemberExpression[object.object.name='process'][object.property.name='env'][property.name='SUPABASE_SERVICE_ROLE_KEY']",
        message:
          "Do not read process.env.SUPABASE_SERVICE_ROLE_KEY directly — use scripts/env/validate.ts's loadEnv() (server-only, redacted). See docs/standards/CODING_STANDARDS.md §4/§10.",
      },
    ],
  },
};

const config = [...next, boundaryRules, bannedPatterns];

export default config;
