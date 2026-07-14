# 04 — Repository Target Structure

**Prompt:** `CG-S3-ARCH-004` (`CG-AABPP-ARCH-039` v0.4.0)
**Runtime output of:** `docs/ai-agent-build-prompt-package/03-architecture-and-plan/39_REPOSITORY_TARGET_STRUCTURE_PROMPT.md`
**Status:** `VERIFIED`

## 0. Checkpoint

| Field | Value |
|---|---|
| Repository | `assujiar/cargogrid.app` |
| Working branch | `agent/cargogrid-autonomous-build` |
| HEAD at authoring time | `e1069f24f1f34a5732fb2a5d2d89cc61ff678adc` (parent of this checkpoint's commit) |
| Precondition | `docs/architecture/01_*.md`, `02_*.md`, `03_*.md` all `VERIFIED` |
| Repository state | Unchanged: 100% documentation (`docs/`, root `AGENTS.md`, `README.md`), zero application code, zero workspace/package-manager topology (`docs/discovery/02_*`, `03_*`, `05_*`) |

### Inputs read (beyond `01–03_*.md`, already fully loaded)

- Tech Arch §7.1 (App Router structure, verbatim), §7.5, §8 (Backend Module Layout, verbatim — already cited in `01_*.md` §3.1), §25 (API Standard: endpoint naming, headers, pagination, error schema, webhook signature, job pattern), §27 (DevOps: environment strategy, trunk-based branching, test pyramid), §28 (CI/CD pipeline stages, migration rules, rollback strategy)
- `docs/discovery/01_REPOSITORY_INVENTORY.md`, `03_TOOLCHAIN_DEPENDENCY_BASELINE.md` — current repository topology (documentation-only, no workspace)

## 1. Scope and method

Per the prompt's instruction #2, every path below is either **concrete** (directly evidenced by an existing blueprint diagram — Tech Arch §7.1's App Router tree, §8's Backend Module Layout tree) or an explicit **bounded pattern** marked `ADR_REQUIRED` where the blueprint states a principle but not an exact folder name (e.g. migrations, tests, infra). No path is invented outside these two categories. Because the repository is confirmed `GREENFIELD` (`docs/discovery/12_*.md`), §7 (current-to-target mapping) has one dominant finding — nothing to preserve at the code level — stated once rather than repeated per row.

## 2. Current structure

```text
/ (repo root)
  AGENTS.md
  README.md (if present)
  docs/
    blueprint/              # 6 authoritative sources — read-only, preserved
    ai-agent-build-prompt-package/   # 430 files — read-only, preserved
    discovery/               # Step 2 evidence — preserved
    architecture/             # Step 3 outputs (this document's own location)
    runtime/                  # canonical persistent context — preserved, actively updated
    build-logs/
```

No `app/`, `src/`, `server/`, `supabase/`, `package.json`, `tsconfig.json`, `.github/`, or any framework/tooling file exists (`docs/discovery/02_*`, `03_*`, `05_*`). There is nothing at the code level to preserve, move, wrap, consolidate, or retire.

## 3. Target structure

Concrete portion — reproduced from Tech Arch §7.1 (App Router) and §8 (Backend Module Layout), extended only by mapping each folder to its owner from `03_DOMAIN_BOUNDARY_MAP.md` §3 (no new folder invented beyond what those two sources already specify):

```text
app/
  (public)/
    login/
    forgot-password/
  (supreme)/
    supreme/
      tenants/
      subscriptions/
      system/
  (tenant)/
    [tenantSlug]/
      dashboard/
      commercial/            # owner: COM
      operations/            # owner: OPS
      finance/               # owner: FIN
      procurement/           # owner: PRC   (bounded pattern, ADR_REQUIRED — not in §7.1's example tree, added by direct analogy to commercial/operations/finance)
      hris/                  # owner: HRS   (bounded pattern, ADR_REQUIRED — same basis)
      support/               # owner: TKT   (bounded pattern, ADR_REQUIRED — same basis)
      loyalty/                # owner: LYL  (bounded pattern, ADR_REQUIRED — same basis)
      admin/                  # owner: Platform (TEN-IAM/CFG/PORTAL-ADM)
  (customer)/
    portal/
      [tenantSlug]/
        dashboard/
        shipments/
        invoices/
        tickets/               # bounded pattern, ADR_REQUIRED — §7.1's example tree stops at invoices/
  api/
    v1/
      tenants/[tenant_id]/...  # REST namespace per domain, Tech Arch §25.2

components/
  ui/
  domain/
  tables/
  forms/

lib/
  auth/
  data/
  permissions/
  tenant/
  config/
  validators/

server/
  queries/
    <domain>.ts              # one file (or folder once large) per domain owner from 03_*.md §3
  mutations/
    <domain>.ts
  actions/
    <domain>-actions.ts
  policies/
    permission-check.ts       # Platform (TEN-IAM), shared kernel — not domain-owned
  integrations/
    <category>.ts             # one file per Tech Arch §26.1 category; owner = INTHUB (Phase 9) / NOTIF (Phase 1 baseline email/WA/SMS)
  jobs/
    <job-type>-job.ts         # owner = JOB (platform primitive)
  contracts/                  # bounded pattern, ADR_REQUIRED — not in §8's example tree; this document adds it as the physical home for 03_*.md §5's 10 public contracts (payload types/validators), since §8's tree has no explicit shared-contract location and DUP-002 requires one canonical lineage/contract source
```

Bounded-pattern portion — principle-evidenced, exact name `ADR_REQUIRED`:

| Concern | Evidence | Bounded pattern | Owner |
|---|---|---|---|
| Database migrations | Tech Arch §9 (PostgreSQL source of truth), §28.2 (versioned migrations), ADR-002 (Supabase Auth+RLS accepted) | `supabase/migrations/*.sql` (standard Supabase CLI convention — the only convention consistent with the ratified Supabase stack; exact naming/timestamp format `ADR_REQUIRED`) | Data/Architecture |
| RLS policy definitions | Tech Arch §11 (RLS mandatory), §11.2 (helper functions in `app.*`/`auth.*` schema) | `supabase/migrations/*.sql` (RLS policies ship as migrations, per Supabase convention) or a dedicated `supabase/policies/` staging area before being folded into a migration — `ADR_REQUIRED` | Security/Data |
| Tests | Tech Arch §27.3 Test Pyramid (unit/integration/RLS/E2E/performance/security/migration/financial) | `tests/unit/`, `tests/integration/`, `tests/rls/`, `tests/e2e/`, colocated `*.test.ts` — exact convention `ADR_REQUIRED` at Prompt 45 | QA |
| Workers/background jobs | Tech Arch §8 (Workers = "Proposed Default"), §32.11 (job table) | `server/jobs/` (already concrete above) plus a possible separate `workers/` process boundary if PostgreSQL-durable-queue workers are split from the Next.js server process — `ADR_REQUIRED`, deferred until Phase 0/1 confirms deployment topology | Architecture/DevOps |
| Design system | Tech Arch §7 (Server/Client Component boundaries), no dedicated design-system section | `components/ui/` (already concrete above) is the design-system home; a separate `design-system/` package is `ADR_REQUIRED` only if Storybook/tokens are introduced — not assumed | Product/UX |
| Scripts/tooling | No blueprint section names this | `scripts/` — bounded pattern, `ADR_REQUIRED` | DevEx |
| Observability | Tech Arch §30 (not yet read in full for this document; referenced generically at §27–28's monitoring/rollback tables) | `lib/observability/` or platform-provider-native (Vercel/Supabase dashboards, no repo folder) — `ADR_REQUIRED` | SRE |
| Infrastructure/config | Tech Arch §6 (Physical Architecture: MVP/Scale-up/Enterprise tiers), §29 (Environments) | `infra/` or provider-native (Vercel project settings, Supabase project config) — no evidence mandates an in-repo IaC folder yet; `ADR_REQUIRED` | DevOps |
| Docs/runbooks (product-facing, distinct from this repo's `docs/`) | Tech Arch §19.3 (every integration needs a runbook) | `docs/runbooks/` — bounded pattern, `ADR_REQUIRED`; must not collide with the existing governance `docs/` tree (§8 below) | Architecture |

## 4. Directory purpose/owner table

| Directory | Purpose | Owner | Server/client boundary |
|---|---|---|---|
| `app/(public)`, `app/(supreme)`, `app/(tenant)`, `app/(customer)` | Route groups — UX/routing boundary only, **not** an authorization boundary (Tech Arch §7.1 guardrail, quoted) | Respective domain per §3 | Server Components by default (Tech Arch §7.2); Client Components only for interaction, never primary data authority (§3 Principle 5) |
| `app/api/v1/**` | Public/webhook/export/import/callback surface | Platform `API-WH` (foundation), domain-specific sub-routes owned by the domain | Route Handlers, server-only |
| `components/ui`, `components/domain`, `components/tables`, `components/forms` | Shared design-system primitives (`ui`) vs. domain-specific composed components (`domain`) | `ui` = Platform/Product; `domain` = respective domain | Client-capable, never a data-authority boundary |
| `lib/auth`, `lib/permissions`, `lib/tenant`, `lib/config`, `lib/validators` | Cross-cutting helpers wrapping Platform primitives | Platform (shared kernel, `01_*.md` §6) | Server-only except where explicitly client-safe (e.g. client-side validator schemas mirrored from server) |
| `lib/data` | Server-only data-fetching helpers | Platform + per-domain | Server-only |
| `server/queries/<domain>.ts` | Read model composition, one file/folder per domain | Per-domain, per `03_*.md` §3 | Server-only |
| `server/mutations/<domain>.ts`, `server/actions/<domain>-actions.ts` | Internal UI mutation via Server Actions | Per-domain | Server-only |
| `server/policies/` | RBAC/permission check — shared kernel, not domain code | Platform (`TEN-IAM`) | Server-only |
| `server/integrations/<category>.ts` | External adapters, one per Tech Arch §26.1 category | `INTHUB`/`NOTIF` (platform) | Server-only, trusted boundary (service role permitted here per Tech Arch §8 Backend Rules) |
| `server/jobs/<job-type>-job.ts` | Background job handlers, PostgreSQL durable queue (RPD-012) | `JOB` (platform primitive) | Server-only |
| `server/contracts/` | Typed payload/validator definitions for the 10 public contracts in `03_*.md` §5 | Platform + producing domain jointly (contract is co-owned by producer's schema, consumer must not redefine it) | Server-only (shared types may be re-exported to client for form validation) |
| `supabase/migrations/` | Versioned DB schema/RLS changes | Data/Architecture | N/A (SQL) |
| `docs/architecture/**` | This Step 3 output set | Architecture (this document's own location) | N/A |
| `docs/runtime/**` | Canonical persistent build context | Runtime build agent | N/A |

## 5. Import and dependency rules

Restates `03_DOMAIN_BOUNDARY_MAP.md` §4/§9 in physical-path form, so a lint rule can be written directly from this table without re-deriving the boundary:

| Rule | Forbidden pattern | Allowed alternative |
|---|---|---|
| No cross-domain query import | `server/queries/operations.ts` importing from `server/mutations/finance.ts` or querying `finance.*` tables directly | Import `server/contracts/billing-readiness.ts` (the named contract) and call `server/queries/finance.ts`'s exported function |
| No portal-to-DB shortcut | `app/(customer)/portal/**` code containing a Supabase client table query | `app/(customer)/portal/**` calls `server/queries/<domain>.ts` (read) or `server/actions/<domain>-actions.ts` (the two intake contracts), scoped by `customer_account_id` |
| No client-side service role | Any `server/**` file importing the Supabase service-role key from a file reachable by a Client Component | Service role usage confined to `server/integrations/`, `server/jobs/`, and Edge Functions only (Tech Arch §8 Backend Rules, verbatim: "Service role hanya dipakai di server trusted boundary, Edge Function, worker, atau admin-only operations. Tidak pernah di browser.") |
| No generic integration abstraction | A `server/integrations/provider-interface.ts` spanning multiple categories | One file per category (RPD-038); shared-code reuse is allowed for genuinely identical logic (e.g. retry/backoff helper in `lib/`), not for a provider-swap abstraction |
| No duplicate canonical master | A second `vendor` or `employee` table/type defined outside `server/queries/procurement.ts` / `server/queries/hris.ts` | Extend the owning domain's type; reference by FK/ID | 
| Reporting is read-only | Any write statement inside `server/queries/reports.ts` or `app/**/dashboard/**` route code | Writes happen only in the owning domain's `mutations`/`actions`; Reporting queries materialized views/reporting tables |

## 6. Contract and generated-code placement

- REST contracts (Tech Arch §25): request/response types and Zod-or-equivalent validators live in `server/contracts/<domain>/`, re-exported to `app/api/v1/**` route handlers and to `server/actions/` for the same-shape internal mutation, so the two never drift (Tech Arch §7.5's Route Handler auth/tenant/authorization/idempotency/rate-limit/error-schema/audit checklist applies uniformly at this one shared entry).
- RLS/RBAC policy tests: colocated with the migration that introduces the policy (`supabase/migrations/`), plus a cross-cutting `tests/rls/` suite asserting the negative case for every table in `03_*.md` §3's namespace list (Tech Arch §11.4).
- Migration validation: CI-gated per Tech Arch §28.1's pipeline (`Migration Check` stage) — exact tooling `ADR_REQUIRED`, but the gate's position (after `Build`, before `Deploy Preview/Staging`) is fixed by that diagram.
- File controls (malware scan, signed URL): implemented once inside `server/integrations/` (the malware-scan provider adapter) and `lib/data/` (signed-URL issuance helper), never duplicated per domain — this is the `DOC` platform primitive's code home.
- Job contracts: `server/jobs/` handler signature matches the job table schema fields from Tech Arch §32.11 (`job_id, tenant_id, job_type, status, priority, payload, attempts, max_attempts, locked_by, locked_until, error, result_url, created_by, created_at, completed_at`) — no job-specific ad hoc payload shape outside `payload` (JSON), validated against the matching `server/contracts/` type.
- Integration-specific code: one file per Tech Arch §26.1 category under `server/integrations/`, each with the ownership fields from that table (business/technical/credential/data/support owner, SLA/timeout/retry, monitoring dashboard, runbook) recorded as a header comment or adjacent `.md` in `docs/runbooks/<category>.md` (bounded pattern, `ADR_REQUIRED`).

## 7. Current-to-target mapping

Per `docs/discovery/02_EXISTING_IMPLEMENTATION_AUDIT.md` and `05_ROUTE_MODULE_INVENTORY.md`: **zero code-level assets exist.** Applying the prompt's required classification, every folder in §3 is `MOVE_INCREMENTALLY`'s opposite case — there is nothing to move, so the correct label is simply **not applicable / create-fresh**, distinct from all six classification values the prompt lists (`PRESERVE_IN_PLACE`, `MOVE_INCREMENTALLY`, `WRAP`, `CONSOLIDATE`, `RETIRE_AFTER_REPLACEMENT`, `UNKNOWN_BLOCKED`) because none presupposes a from-scratch repository. The only assets classified `PRESERVE_IN_PLACE` are the pre-existing documentation trees, unchanged from `01_MODULE_DEPENDENCY_MAP.md` §8: `docs/blueprint/**`, `docs/ai-agent-build-prompt-package/**`, `docs/ai-agent-build-prompt-package/00-control/**`, `docs/runtime/**`, `docs/discovery/**`, `docs/architecture/**` (this Step 3 output set itself). No file is `WRAP`/`CONSOLIDATE`/`RETIRE_AFTER_REPLACEMENT` and no `UNKNOWN_BLOCKED` item exists — the greenfield decision (`docs/discovery/12_*.md`) already resolved this ambiguity at Step 2.

## 8. Incremental transition sequence

Since there is no existing code, "transition" here means the **order in which the target structure's folders are first created**, not a migration off legacy code. Sequenced to match the phase order already fixed in `01_MODULE_DEPENDENCY_MAP.md` §10:

| Slice | Phase | Folders created | Compatibility constraint | Rollback | Verification |
|---|---|---|---|---|---|
| 1 | 0 (Foundation) | `supabase/` (empty project scaffold), `.gitignore` (`ISS-2026-003`), root config (`package.json`, `tsconfig.json`) | None — first commit | `git revert` | Toolchain baseline installs cleanly |
| 2 | 1 (Platform Core) | `app/(public)`, `app/(supreme)`, `app/(tenant)/[tenantSlug]/admin`, `lib/**`, `server/queries|mutations|actions/` (platform-only files), `server/policies/`, `server/jobs/`, `components/ui/`, `supabase/migrations/` (first tenant/IAM migrations) | No business-domain folder created yet — platform-only, matches `01_*.md` Phase 1 scope exactly | `git revert` the slice's commits; no data exists yet so no data rollback needed | Platform Core capability prompts (`105`–`140`) each verify their own slice |
| 3 | 2 (Commercial) | `app/(tenant)/[tenantSlug]/commercial`, `server/queries/commercial.ts` etc., `server/contracts/commercial/` | Must not modify Phase-1 platform folders except additive registration (e.g. new route group entry) | `git revert` | `141`–`165` capability prompts |
| 4 | 3 (Operations, basic) + Portal (basic) | `app/(tenant)/[tenantSlug]/operations`, `app/(customer)/portal/[tenantSlug]/{dashboard,shipments}`, `server/queries/operations.ts`, `server/contracts/operations/` | Portal folder created but scoped strictly read + 2 intake contracts, per §5's import rules | `git revert` | `166`–`188` capability prompts |
| 5 | 4 (Finance) | `app/(tenant)/[tenantSlug]/finance`, `server/queries/finance.ts`, `server/contracts/finance/`, `supabase/migrations/` (journal/AR/AP schema) | Idempotent-posting key (Tech Arch §24.5) must exist before any posting mutation ships | `git revert`; financial-table migrations get "extra review" per Tech Arch §28.2 | `189`–`218` capability prompts |
| 6 | 5 (Advanced TMS/WMS) | Extends `operations/` in place — no new top-level folder, per `01_*.md` `CON-004` (same owner throughout) | Must not fork a second `operations-advanced/` tree | `git revert` | `219`–`248` capability prompts |
| 7 | 6 (Procurement/Vendor) | `app/(tenant)/[tenantSlug]/procurement`, `server/queries/procurement.ts` | Resolves `ADR-CAND-ARCH-001` (vendor-rate canonical table) at this slice, per `02_*.md` §14 | `git revert` | `249`–`271` capability prompts |
| 8 | 7 (HRIS/Ticketing) | `app/(tenant)/[tenantSlug]/{hris,support}`, `server/queries/{hris,tickets}.ts` | Resolves `ADR-CAND-ARCH-002` (employee↔user FK) at this slice | `git revert` | `272`–`297` capability prompts |
| 9 | 8 (Portal full/Loyalty) | Extends `app/(customer)/portal/**` in place (per `CON-005`, same owner throughout), adds `app/(tenant)/[tenantSlug]/loyalty` | Must not fork a second portal tree | `git revert` | `298`–`327` capability prompts |
| 10 | 9 (Intelligence/Enterprise) | `server/integrations/<17 categories>/`, `server/jobs/` (AI/reporting jobs), `docs/runbooks/` | RPD-038 no-generic-abstraction rule applies to every new integration file | `git revert` | `328`–`367` capability prompts |

No-big-bang constraint: each slice is scoped to its phase's own folders only, matching the "one feature slice, one module boundary, one branch, one objective, normally 1–3 migrations and 5–15 changed files" rule already binding on architecture tasks (Step 3 README §5) and carried forward as the same constraint for implementation-phase tasks.

## 9. Enforcement gates

- **Lint boundary rule** (Prompt 41 or Phase 0 tooling setup): encodes §5's import-rule table as an ESLint import-boundary config (e.g. `eslint-plugin-boundaries` or an equivalent restricted-imports rule) — fails CI on any forbidden pattern in §5.
- **CODEOWNERS-equivalent ownership file**: one entry per directory in §4, mapping to the owning domain team — bounded pattern, `ADR_REQUIRED` for exact tool (GitHub `CODEOWNERS` file is the concrete default given GitHub hosting, per `docs/discovery/01_*.md`).
- **Architecture tests**: a CI step asserting `server/queries/reports.ts` and any `app/**/dashboard/**` route contain no write statement (mirrors `03_*.md` §9 violation pattern 5); a CI step asserting no file under `app/(customer)/portal/**` imports a Supabase client directly (mirrors violation pattern 3).
- **CI checks**: Tech Arch §28.1's pipeline (`Lint/Typecheck → Unit/Integration → RLS/Security → Build → Migration Check → Deploy Preview/Staging → E2E/Smoke → Manual Gate if Prod → Production Deploy → Post-deploy Monitoring`) is adopted as-is; this document adds no new stage, only maps §4/§5's folders onto the existing stage names.
- **Documentation indices**: `docs/runbooks/<category>.md` per integration (§6); this document itself becomes the index Prompt 40+ cross-references for "where does X live."

## 10. ADR candidates (new, specific to repository structure)

| ID | Question | Constraint | Recommendation | Owner | Blocking state |
|---|---|---|---|---|---|
| `ADR-CAND-ARCH-009` | Exact migration file naming/versioning convention (`supabase/migrations/<timestamp>_<name>.sql` vs. an alternative)? | Must work with `supabase db diff`/`supabase migration` CLI tooling (ratified Supabase stack) | Adopt the Supabase CLI's own default timestamp-prefixed convention — no reason to deviate | Data/DevEx | `ADR_REQUIRED`, non-blocking — resolve at Phase 0 toolchain setup (before first migration, per `ISS-2026-003`'s "add before first code" precedent) |
| `ADR-CAND-ARCH-010` | Does `server/contracts/` exist as a first-class folder from Phase 1, or do contracts stay inline in `server/queries|mutations` until a second consumer forces extraction? | `01_*.md` §11 R1/R3 forbid cross-domain direct imports, which implies contracts must exist before the second domain (Phase 2, Commercial→Operations) needs one | Create `server/contracts/` from Phase 1 (Platform Core) so the convention is established before any cross-domain edge exists, rather than retrofitting at Phase 2 | Architecture | `ADR_REQUIRED`, non-blocking — resolve at Prompt 40/Platform Core kickoff (Prompt 104) |
| `ADR-CAND-ARCH-011` | Are `procurement/`, `hris/`, `support/`, `loyalty/` route groups and query files created empty at Phase 1 (stub, unrouted) or only when their phase begins (Phase 6/7/7/8)? | Step 3 README §5 forbids "false parallelism"; empty stubs risk violating the AGENTS.md rule against "empty stubs, dead routes... to a completed task" | Create each domain's folder only when its phase begins (§8's transition sequence already assumes this) — no pre-created empty stubs | Architecture | `ADR_REQUIRED`, non-blocking — resolve as a standing convention at Phase 0 kickoff |

## 11. Risks

| ID | Description | Category | Severity | Recommended handling |
|---|---|---|---|---|
| `MDM-RISK-005` | Seven near-identical per-domain folders (`commercial/`, `operations/`, `finance/`, `procurement/`, `hris/`, `support/`, `loyalty/`) created across 6 different phases by potentially different sessions/agents risk drifting naming conventions (singular vs. plural, `-actions.ts` suffix consistency) if no single style guide is written down before Phase 1 starts. | Consistency/tooling risk | Low | Capture the exact naming convention (already implied by this document's §3/§4 tables) in a short `CONTRIBUTING.md`-style note at Phase 0 kickoff, so later phases don't each reinvent it. |

## 12. Rollback principles

- Every slice in §8 is `git revert`-able independently because no slice depends on production data existing yet (repository is greenfield through at least Phase 4's first invoice).
- Frontend rollback = redeploy previous build (Tech Arch §28.3); API rollback = versioned endpoint/previous deploy; DB schema rollback = forward-fix preferred, down-migration only if safe; config rollback = version rollback; feature rollback = flag disable; data rollback = restore only for disaster, business correction for transactions. This document adopts Tech Arch §28.3's table as-is — no repository-structure-specific rollback exception is introduced.
- No migration/deployment/CI change is made by this document itself (Step 3 README §7 scope contract) — §8's phase sequencing is a plan for later phases to execute, not an action taken now.

## 13. Completion statement

Target structure aligns with the verified greenfield topology (`docs/discovery/02_*`, `05_*`) and with `03_DOMAIN_BOUNDARY_MAP.md`'s domain boundaries (§4's directory-owner table maps 1:1 onto `03_*.md` §3's ownership catalogue). No preserved asset (`docs/blueprint/**`, `docs/ai-agent-build-prompt-package/**`, `docs/runtime/**`, `docs/discovery/**`) is touched or reclassified. No tenant fork and no broad rewrite is introduced — §8's transition sequence creates each domain's folder exactly once, at its own phase, matching the phase order already fixed in Prompts 36–38. Later tasks (Phase 0 foundation prompts, Prompt 40 Database Schema Workstream) have explicit allowed/forbidden path guidance via §5's import rules and §9's enforcement gates.

Next eligible prompt: `03-architecture-and-plan/40_DATABASE_SCHEMA_WORKSTREAM_PROMPT.md` → `docs/architecture/05_DATABASE_SCHEMA_WORKSTREAM.md`.
