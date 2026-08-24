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

// docs/standards/CODING_STANDARDS.md §10/§11, plus the CargoGrid Chart System's own
// governance rule (docs/design-system/09_CHARTS.md, "Apache ECharts is the only
// approved chart engine... never instantiate directly in feature pages"). All three
// selectors MUST live in one "no-restricted-syntax" rule array, not two separate
// config objects — ESLint flat config replaces (does not merge) a rule's value when
// two matching config objects both set the same rule key, so a second object setting
// "no-restricted-syntax" would silently discard the first's selectors. Found and
// fixed during an earlier checkpoint (docs/build-log/phase-00/PH0-89.md §5) — proven
// with --print-config showing the SELECT * selector missing before that fix. No
// `ignores` exemption is needed for the service-role selector: scripts/env/** reads
// variables via computed bracket access (`source[def.name]`), never the literal
// dot-access this selector matches (verified: zero matches for the literal form
// anywhere in scripts/). The echarts selector, by contrast, DOES need an `ignores`
// scope excluding `components/charts/**` (the one place `echarts.init` is meant to
// run) — implemented as a *separate* config object below (`chartGovernancePatterns`)
// rather than a third selector in this one, specifically so its file scope can differ
// from this object's (unscoped) one; the two objects' `files`/`ignores` never overlap
// for the same file, so the "replaces, doesn't merge" hazard above does not apply
// between them.
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

// CargoGrid Chart System governance: `echarts.init(...)` may only run inside
// `components/charts/` (today, only `use-chart.ts`). A feature page instantiating
// ECharts directly would bypass the shared theme/accessibility/resize/dispose
// lifecycle this whole system exists to centralize. The selector matches the literal
// `echarts.init(...)` call shape (the same convention this checkpoint's own code
// uses) — a deliberately obfuscated/renamed import evades it, the same acknowledged
// limitation the SELECT * selector above already has.
const chartGovernancePatterns = {
  ignores: ["components/charts/**"],
  rules: {
    "no-restricted-syntax": [
      "error",
      {
        selector: "CallExpression[callee.type='MemberExpression'][callee.object.name='echarts'][callee.property.name='init']",
        message:
          "Do not call echarts.init() outside components/charts/ — use the shared <Chart> component (components/charts/chart.tsx) instead, so theme/accessibility/resize/dispose stay centralized (docs/design-system/09_CHARTS.md).",
      },
    ],
  },
};

// ISS-2026-168: `lib/supabase/service-role.ts`'s own header comment claims a "bundle
// scan" (`scripts/env/client-guard.ts`) enforces that this module never reaches a
// client bundle -- it does not; `client-guard.ts` is only a runtime `typeof window`
// check, not a static scan, and it does not even look for this import path (see its
// own header comment, updated alongside this rule). The only real *static* control
// was `bannedPatterns`'s `no-restricted-syntax` selector above, which matches literal
// `process.env.SUPABASE_SERVICE_ROLE_KEY` dot-access -- `service-role.ts`'s own
// `requireEnv()` helper evades that selector by reading `process.env[name]` via
// bracket access. This rule closes that gap at the import boundary instead: no file
// anywhere may import `lib/supabase/service-role` (with or without its explicit
// `.ts` extension, however many `../` segments or a `@/` alias precede it) full stop.
//
// This repository has no directory or filename convention that reliably distinguishes
// Client Components from Server Components/Server Actions/Route Handlers -- "use
// client" is a top-of-file directive, not a naming pattern (confirmed: e.g.
// `app/(tenant)/[tenantSlug]/procurement/vendors/vendor-directory-panel.tsx` is a
// Client Component, `app/(public)/tracking/[token]/page.tsx` is a Server Component,
// and both live under `app/`; `*-panel.tsx` is not a safe signal either way). A glob
// scoped to only client-component paths is therefore not available, so this rule
// takes the opposite, still-bounded shape used by `chartGovernancePatterns` above:
// flag the import everywhere, then `ignores` the exact file list of every current,
// audited-legitimate importer (Server Actions, Route Handlers, and Server Components
// under `app/`, plus `lib/portal/*-deps.server.ts`, `lib/api-gateway/authenticate.
// server.ts`, and `scripts/jobs/*-worker.ts` -- all confirmed server-only code that
// already owns the service-role call). A brand-new importer -- a Client Component or
// anything else not on this list -- is not exempted and trips the rule immediately;
// extending legitimate access requires deliberately adding the new file to this list,
// which is itself a lightweight review gate on top of the import boundary. Square
// brackets in Next.js dynamic-segment directory names (e.g. `[tenantSlug]`,
// `[token]`) are escaped below because flat config's glob matching treats unescaped
// `[...]` as a character class, not a literal path segment (verified with
// `eslint --print-config` against a throwaway rule before adopting this pattern).
const serviceRoleImportGuard = {
  ignores: [
    "app/(public)/careers/\\[tenantSlug\\]/\\[postingToken\\]/actions.ts",
    "app/(public)/careers/\\[tenantSlug\\]/\\[postingToken\\]/page.tsx",
    "app/(public)/careers/\\[tenantSlug\\]/page.tsx",
    "app/(public)/quote-decision/\\[token\\]/actions.ts",
    "app/(public)/quote-decision/\\[token\\]/page.tsx",
    "app/(public)/tracking/\\[token\\]/page.tsx",
    "app/(public)/vendor-intake/\\[token\\]/actions.ts",
    "app/(public)/vendor-intake/register/\\[tenantSlug\\]/actions.ts",
    "app/(public)/vendor-intake/register/\\[tenantSlug\\]/page.tsx",
    "app/(tenant)/\\[tenantSlug\\]/admin/api-keys/actions.ts",
    "app/(tenant)/\\[tenantSlug\\]/customer-quotes/actions.ts",
    "app/(tenant)/\\[tenantSlug\\]/operations/shipment-orders/\\[shipmentOrderId\\]/actions.ts",
    "app/(tenant)/\\[tenantSlug\\]/procurement/assessments/actions.ts",
    "app/(tenant)/\\[tenantSlug\\]/procurement/compliance/vendors/actions.ts",
    "app/(tenant)/\\[tenantSlug\\]/procurement/vendors/\\[masterRecordId\\]/financial/actions.ts",
    "app/api/tracking/driver-mobile/route.ts",
    "app/api/webhooks/finance-payment-gateway/\\[connectionId\\]/route.ts",
    "app/api/webhooks/logistics-partner/\\[connectionId\\]/route.ts",
    "app/api/webhooks/third-party-gps/\\[connectionId\\]/route.ts",
    "lib/api-gateway/authenticate.server.ts",
    "lib/portal/supreme-admin-guard-deps.server.ts",
    "lib/portal/tenant-admin-guard-deps.server.ts",
    "scripts/jobs/external-sync-worker.ts",
    "scripts/jobs/finance-bank-feed-sync-worker.ts",
    "scripts/jobs/logistics-partner-sync-worker.ts",
    "scripts/jobs/notification-delivery-worker.ts",
    "scripts/jobs/webhook-delivery-worker.ts",
  ],
  rules: {
    "no-restricted-imports": [
      "error",
      {
        patterns: [
          {
            group: ["**/supabase/service-role", "**/supabase/service-role.ts"],
            message:
              "service-role client must only be imported from Server Actions, Route Handlers, or Server Components -- never from a Client Component (ISS-2026-168, docs/standards/CODING_STANDARDS.md §4/§10). If this is genuinely server-only code, add the file to serviceRoleImportGuard's `ignores` list in eslint.config.js after confirming it never runs in a Client Component.",
          },
        ],
      },
    ],
  },
};

// PLT-135, CG-S6-PLT-032: `app/`'s first real pages mean `.next/` (the build output
// directory) now actually gets created locally/in CI -- `eslint-config-next`'s bundled
// shareable config (consumed directly here as a flat-config array, not through the
// deprecated `next lint` CLI wrapper that used to inject this ignore automatically)
// does not exclude it on its own. Explicit and load-bearing, not decorative: without
// this, `eslint .` lints Next's own minified production bundle as if it were source.
// ATW-226D: services/gps-gateway is a standalone, independently-deployed Node package
// (its own package.json, its own tsconfig.json, own typecheck/test scripts) -- deliberately
// not wired into this repository's own Next.js-oriented lint config, the identical
// "independent deployment from Vercel" boundary tsconfig.json's own exclude entry already
// draws. Its own gate surface (typecheck + test, no lint) is disclosed in its own README.md.
const ignores = {
  ignores: [".next/**", "playwright-report/**", "test-results/**", "services/**"],
};

const config = [ignores, ...next, boundaryRules, bannedPatterns, chartGovernancePatterns, serviceRoleImportGuard];

export default config;
