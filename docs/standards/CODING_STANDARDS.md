# CargoGrid Coding Standards and Architecture Enforcement

**Established by:** `CG-S5-PH0-010` (Prompt 89 — Coding Standards and Architecture Enforcement)
**Status:** Active — documentation + bounded automated enforcement, no broad reformat/refactor performed

**Source note:** Prompt 89 §6 cites "Master Prompt §§8–21." No file literally titled "Master Prompt" is tracked in this repository (confirmed by search); every other prompt in the package that cites "Master Prompt §N" resolves, by section-number match and content, to `docs/blueprint/04_CargoGrid_Technical_Architecture_Security_Integration.md` — the same document cited elsewhere in this build as "Tech Arch §N" (e.g. `docs/architecture/11_DEVOPS_WORKSTREAM.md`'s "Tech Arch §27.2"). §§8–21 of that document are: Backend Architecture, Database Architecture, Multi-tenancy, RLS, RBAC, Configuration/Workflow/Approval/Notification/Document/Reporting/Integration/Billing/Loyalty Engines — exactly the range a "coding standards and architecture enforcement" task needs. This interpretation is recorded explicitly, not silently assumed; see `docs/build-log/phase-00/PH0-89.md` §2.

This document distills **normative, enforceable conventions** from architecture already ratified in `docs/architecture/**` and `docs/blueprint/04_*.md` — it does not re-derive that architecture, and it does not license a rewrite of any existing file (business rule §24: "no broad reformat/refactor; new controls cannot silently rewrite user code").

## 1. Naming conventions

- **Files:** `kebab-case.ts` (matches this repository's own `scripts/git/check-worktree-collision.ts` etc.); one file per domain query/mutation set once a domain exists (`server/queries/<domain>.ts`, per Tech Arch §8's Backend Module Layout, reproduced in §3 below).
- **Variables/functions:** `camelCase`. **Types/interfaces/classes:** `PascalCase`. **Constants (module-level, immutable registry/config):** `SCREAMING_SNAKE_CASE` (e.g. `ENV_REGISTRY`, `PROTECTED_PATH_RULES` — this repository's own established pattern from `PH0-086`/`PH0-087`).
- **Custom error classes:** `<Domain>Error` extending `Error`, with a `name` field set in the constructor (this repository's own `EnvValidationError` pattern, `scripts/env/validate.ts`) — never a bare `throw new Error(string)` for a condition a caller needs to distinguish programmatically.
- **WBS/capability IDs:** never invented ad hoc — always the exact `CG-WBS-<n>`/phase-short-code form already registered in `docs/architecture/13_FULL_WORK_BREAKDOWN_STRUCTURE.md` §4 (already-binding rule, restated here for the coding-standards context).

## 2. Module and import boundaries (automated where possible)

Directly reproduced from `docs/architecture/03_DOMAIN_BOUNDARY_MAP.md` §4 ("Allowed dependency directions") and `01_MODULE_DEPENDENCY_MAP.md` §3 — not re-derived:

1. **Platform kernel → every domain, one direction only.** The kernel (`lib/**`, `server/policies/**`, and the Platform-primitive slice of `server/queries|mutations|actions/` — `TEN-IAM`, `CFG`, `WF`, `APPR`, `STAT`, `NUM`, `FORM`, `NOTIF`, `DOC`, `API-WH`, `IMPEXP`, `JOB`, `FLAG`, `GEO`) never depends on a business domain (`COM`/`OPS`/`FIN`/`PRC`/`HRS`/`TKT`/`CPT`/`LYL`). **Automated** — `eslint.config.js`'s `import/no-restricted-paths`, §4 below.
2. **No business domain may depend on `CPT` (Customer Portal) or `REP` (Reporting).** Both are strictly downstream/leaf nodes (`03_*.md` §4, verbatim). **Automated** for the direct-import case — `eslint.config.js`, §4 below.
3. **Business domain → business domain** follows only the named edges in `01_*.md` §3.3 (e.g. `COM → OPS`, `OPS → FIN`, `FIN → LYL`, `PRC → OPS`/`FIN`, `HRS → APPR`/`OPS`/`FIN`, `TKT → OPS`/`FIN`/`PRC`/`CPT`) — no domain may call another domain not named there. **Not automated** (the full pairwise matrix is large, file structure for most domains doesn't exist yet, and several edges are read-only-snapshot exceptions requiring semantic review, not just a path check — `01_*.md` §3.3's own note on `COM→OPS` revenue-snapshot). Enforced by code review against `01_*.md` §3.3 until a domain's real file structure exists and a bounded path rule can be added without guessing at not-yet-real paths.
4. **`CPT` reaches an owning domain only through its query/action layer or the two named intake contracts** (`CPT-QBK` → `COM` lead/opportunity intake) — never a direct database shortcut (`03_*.md` §4; `01_*.md` §3.3, "Portal must never bypass the owning domain's server query/action layer"). **Not automated** (requires distinguishing "goes through the approved query function" from "constructs its own query," a semantic check path-based rules cannot make) — enforced by code review; a future capability could add a custom ESLint rule once real Supabase client call-sites exist to analyze.

## 3. Backend layering (Tech Arch §8, reproduced)

```text
server/
  queries/<domain>.ts        # read model, screen-level data composition
  mutations/<domain>.ts      # internal UI mutation
  actions/<domain>-actions.ts
  policies/permission-check.ts
  integrations/<category>.ts
  jobs/<job-type>-job.ts
  contracts/<domain>/        # bounded pattern, shared request/response types + validators (04_REPOSITORY_TARGET_STRUCTURE.md §3)
```

**Backend rules (Tech Arch §8, binding, verbatim):**
- Every mutation has an actor, tenant context, permission check, validation, idempotency where needed, and audit.
- A DB transaction is used for any operation that must be atomic.
- The business-rule engine reads the published/effective config version — never a hardcoded tenant-specific branch (`if (tenantId === 'x') { ... }` is forbidden by this rule, not merely discouraged).
- The service-role key is used only in a trusted server boundary, Edge Function, worker, or admin-only operation — **never in the browser.** **Automated** (build on this repository's own `scripts/env/schema.ts`/`client-guard.ts` pattern from `PH0-086`; `eslint.config.js`'s `no-restricted-syntax`, §4 below, adds a static check for the same invariant).

## 4. Automated checks implemented this checkpoint

All added to `eslint.config.js`, using `eslint-plugin-import` (already a transitive dependency of `eslint-config-next`, installed since `PH0-085` — no new dependency added, per §20 task 3's "using existing toolchain where possible"):

| Rule | Enforces | Fires today? |
|---|---|---|
| `import/no-restricted-paths` zone "kernel-never-imports-domain" | §2 rule 1 | Not yet — `lib/`/`server/` don't exist until Phase 1; configured now, inert until then (same pattern as `ADR-0001`'s domain-folder rule and `scripts/git/check-protected-paths.ts`) |
| `import/no-restricted-paths` zone "no-domain-imports-cpt-or-rep" | §2 rule 2 | Not yet, same reason |
| `no-restricted-syntax` — literal `SELECT *` in a string/template literal | NFR-PERF-002 ("avoid `SELECT *`", `00-control/05_REQUIREMENT_COVERAGE_MATRIX.md` §4) | **Yes, today** — fires on any file, not gated on a folder that doesn't exist yet |
| `no-restricted-syntax` — `process.env.SUPABASE_SERVICE_ROLE_KEY` accessed outside `scripts/env/**` | Tech Arch §8's "service role never in the browser," operationalized as "never read the raw var outside the one module whose job is reading it" | **Yes, today** |

Every rule above was proven to fire against a real, intentional fixture violation this checkpoint — see `docs/build-log/phase-00/PH0-89.md` §5 for the exact commands and output. None was proven only by reading the config; each was actually triggered.

## 5. Error handling, logging, and redaction

- **Error handling:** typed error classes (§1), never a bare string throw for a condition a caller branches on. `EnvValidationError` (`scripts/env/validate.ts`) is the reference pattern.
- **Logging/redaction:** never log a raw secret/PII value. `scripts/env/redact.ts`'s `describeForAudit`/`fingerprint` pattern (name + classification + set-state, or a non-reversible fingerprint) is the binding pattern for any future logging that touches a `secret`-classified value (`scripts/env/schema.ts`'s classification registry).

## 6. Test conventions

Ratified at `PH0-091` (Testing Foundation, `ADR-0007`/`ADR-0008`) — see `docs/standards/TESTING_STANDARDS.md` for the full runner/naming/isolation/flake/factory convention. Summary: Node's built-in `node:test` + `node:assert/strict` for unit/integration/component (server-side), one `.test.ts` colocated next to the module it tests, positive cases first then negative/failure cases, a named regression test pinning any fix made during authoring (e.g. `check-worktree-collision.test.ts`'s "regression guard for the origin/main-vs-stale-local-main bug"); `@playwright/test` + `@axe-core/playwright` for E2E/visual-regression/accessibility (`e2e/*.spec.ts`). No longer provisional.

## 7. Migration conventions

`AGENTS.md` (binding, restated): never edit an applied migration; add a new migration. Additive/expand-and-contract patterns preferred where risk warrants it (`AGENTS.md` "Scope and refactoring"). No migration exists yet — this section is the standing rule for the first one (Phase 1).

## 8. API conventions

Deferred to `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` (already `VERIFIED`, not re-derived here): shared Zod-or-equivalent validator per domain contract (`server/contracts/<domain>/`, `ADR-0003` — Zod already adopted for the environment schema, recommended for this too), REST `/v1` + GraphQL developed together, every mutation carries an idempotency key where externally reachable, every entry surface re-enters the same 8-stage auth/tenant/permission/validation/audit flow regardless of REST/GraphQL/Server Action/job origin.

## 9. UX conventions

Deferred to `docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` (already `VERIFIED`): Server Components by default for sensitive/data-heavy views, Client Components at interaction boundaries (`AGENTS.md` "Stack baseline"); component design-token/library ADR is `PH0-090`'s own deliverable (`ADR-CAND-ARCH-020/021`), not preempted here.

## 10. Security bans (binding, not merely discouraged)

- No service-role/secret value in a `NEXT_PUBLIC_`-prefixed variable or in any browser-reachable code path (§4's automated check; `scripts/env/schema.ts`'s self-check already enforces this for the env-variable declaration itself).
- No raw SQL/query bypass of RLS from application code — RLS is mandatory for tenant-scoped tables unless an approved, tested compensating control exists (`AGENTS.md`, `docs/architecture/06_RLS_RBAC_WORKSTREAM.md`).
- No unvalidated input reaching a mutation — every mutation validates through its Zod-or-equivalent contract (§8) before touching data.
- No unauthorized data access — action/scope/record/field/status/value/export/print/masking policy is enforced server-side, never UI-visibility-only (`AGENTS.md`, restated).

## 11. Performance bans (binding, not merely discouraged)

- No `SELECT *` (NFR-PERF-002, §4's automated check).
- No unbounded read / full-table-to-browser transfer — server-side pagination is mandatory (NFR-PERF-003).
- No N+1 query pattern (NFR-PERF-001) — not automatable via static lint without a real query layer to analyze; enforced by code review until Phase 1's `server/queries/**` exists, at which point a targeted rule (e.g. flagging a query call inside a loop body) becomes feasible and should be added then, not guessed at now.
- Any optimization claim requires a measurement, never an assumption (Prompt 89 §17: "require measurement for optimization").

## 12. Exception and suppression governance

Business rule §24 (binding): "Suppression needs reason/owner/expiry and cannot waive security/integrity." Every `eslint-disable`/`@ts-expect-error`/equivalent suppression comment in this repository must carry, on the same line or the line immediately above:

```
// eslint-disable-next-line <rule-name> -- SUPPRESS(owner=<name-or-handle>, reason=<short-text>, expires=<YYYY-MM-DD-or-NONE>, adr=<ADR-id-or-NONE>)
```

- `owner` and `reason` are mandatory. `expires=NONE` is allowed only for a standing, ratified exception with an `adr` reference (e.g. RPD-022's Supreme Admin absolute-CRUD exception, if it ever needs a lint suppression rather than a design-level allowance). A suppression that would waive a **security or data-integrity** rule (§10 above) is never permitted regardless of metadata — it must be fixed or the underlying rule changed via ADR, not suppressed.
- **Automated** — `scripts/standards/check-suppressions.ts` (this checkpoint) scans for `eslint-disable`/`@ts-expect-error` comments missing this metadata format and fails with the exact file/line. No suppression exists in this repository yet (verified — `grep -rn "eslint-disable\|@ts-expect-error"` across every tracked file returns nothing outside this document's own example above), so this is a preventive check, not a retrofit.

## 13. Rollout note

No existing file was reformatted or refactored to adopt these standards (business rule §24: "cannot silently rewrite user code") — this repository's existing code (`scripts/env/**`, `scripts/git/**`) already followed every convention above by construction (it is the source several conventions were extracted *from*, not retrofitted *to*), confirmed by re-running `pnpm run lint`/`typecheck`/`test` unchanged after this checkpoint's config additions (`docs/build-log/phase-00/PH0-89.md` §5).
